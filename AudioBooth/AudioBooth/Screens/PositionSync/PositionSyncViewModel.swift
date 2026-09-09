import Combine
import Foundation
import Logging
import Models
import ReadiumShared
import UIKit

final class PositionSyncViewModel: PositionSyncSheet.Model {
  enum SyncError: LocalizedError {
    case noReadingPosition
    case notFound

    var errorDescription: String? {
      switch self {
      case .noReadingPosition:
        String(localized: "Couldn't tell where you stopped reading. Open the ebook first.")
      case .notFound:
        String(
          localized:
            "Couldn't find your reading position in the audiobook. It may not be narrated in this recording."
        )
      }
    }
  }

  private let context: BookSyncContext
  private let ebooks = EbookTextIndexLoader()
  private var search: Task<Void, Never>?
  private var ebookWord: Int?
  private var isAtSectionStart = false
  private var expectedChapter: String?

  private static let chapterSnapWindow: TimeInterval = 60
  private static let wholeSecondNudge: TimeInterval = 0.1

  init(context: BookSyncContext) {
    self.context = context
    super.init()
  }

  isolated deinit {
    search?.cancel()
  }

  override func onAppear() {
    guard case .searching(let step) = phase, step.isEmpty else { return }
    start()
  }

  override func onRetryTapped() {
    start()
  }

  override func onCancelTapped() {
    search?.cancel()
    search = nil
    onFinished?()
  }

  override func onDismiss() {
    search?.cancel()
    search = nil
    onFinished?()
  }

  override func onSkipTapped() {
    guard case .result(let result) = phase else { return }

    guard let player = PlayerManager.shared.current as? BookPlayerModel,
      player.id == context.bookID
    else {
      Toast(error: String(localized: "Open this audiobook in the player first.")).show()
      return
    }

    player.seekToTime(result.time)
    if let ebookProgress = (try? MediaProgress.fetch(bookID: context.bookID))?.ebookProgress {
      PositionSyncOffer.recordCheck(
        .toAudiobook,
        bookID: context.bookID,
        audioTime: result.time,
        ebookProgress: ebookProgress
      )
    }
    Haptics.impact(.medium)
    onFinished?()
  }

  private func start() {
    guard #available(iOS 26.0, *) else {
      phase = .failed(String(localized: "Catch Up needs iOS 26 or later."))
      return
    }

    guard let source = context.source else {
      phase = .failed(String(localized: "Download this audiobook to catch up."))
      return
    }

    guard context.hasEbook else {
      phase = .failed(String(localized: "Download this book's ebook to catch up."))
      return
    }

    search?.cancel()
    ebookWord = nil
    isAtSectionStart = false
    expectedChapter = nil
    phase = .searching(String(localized: "Finding where you stopped reading…"))

    search = Task { [weak self] in
      await self?.runSearch(source: source)
    }
  }

  @available(iOS 26.0, *)
  private func runSearch(source: NarrationSource) async {
    do {
      guard let placed = await readingPosition() else {
        guard !Task.isCancelled else { return }
        phase = .failed(SyncError.noReadingPosition.localizedDescription)
        return
      }
      try Task.checkCancellation()

      if let chapterStart = placed.chapterStart {
        AppLogger.readAlong.info(
          "Position Sync: the reading position is a chapter start, using \(Int(chapterStart))s directly"
        )
        present(time: chapterEntry(at: chapterStart), isExact: true)
        return
      }

      phase = .searching(String(localized: "Preparing speech recognition…"))
      let locale = try await ReadAlongAvailability.prepare(preferred: context.locale)
      try Task.checkCancellation()

      let windows = PageSearchPlan.windows(
        for: placed.excerpt.page,
        chapters: context.chapters,
        duration: context.duration,
        playhead: playhead,
        ebookEstimates: placed.estimates
      )

      guard !windows.isEmpty else {
        phase = .failed(SyncError.notFound.localizedDescription)
        return
      }

      let first: String = windows[0].chapterTitle ?? "the whole book"
      AppLogger.readAlong.info(
        "Position Sync: searching \(windows.count) window(s), first is \(first)"
      )
      phase = .searching(String(localized: "Listening to the audiobook…"))

      let located = try await PageLocator.locate(
        page: placed.excerpt.page,
        windows: windows,
        duration: context.duration,
        source: source,
        locale: locale,
        onProgress: progressHandler()
      )
      try Task.checkCancellation()

      finish(located)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      AppLogger.readAlong.error("Position Sync failed: \(error)")
      phase = .failed(error.localizedDescription)
    }
  }

  private func readingPosition() async -> (
    excerpt: EbookExcerpt.Excerpt,
    estimates: [AudioPositionEstimator.Estimate],
    chapterStart: TimeInterval?
  )? {
    guard let url = context.ebookURL else { return nil }

    let ebook = await ebooks.load(
      bookID: context.bookID,
      url: url,
      chapters: context.chapters,
      duration: context.duration
    )
    guard let ebook, !Task.isCancelled else { return nil }

    var excerpt: EbookExcerpt.Excerpt?
    if let location = context.ebookLocation, let locator = try? Locator(jsonString: location) {
      excerpt = EbookExcerpt.at(locator: locator, index: ebook.index, sections: ebook.sections)
    }
    if excerpt == nil, let progression = context.ebookProgress, progression > 0 {
      excerpt = EbookExcerpt.at(progression: progression, index: ebook.index)
    }

    guard let excerpt else {
      AppLogger.readAlong.info("Position Sync: the reading position could not be placed in the ebook")
      return nil
    }

    ebookWord = excerpt.word
    isAtSectionStart = excerpt.isSectionStart

    let estimates = AudioPositionEstimator.estimates(
      forWord: excerpt.word,
      map: ebook.map,
      chapters: context.chapters,
      duration: context.duration,
      totalWords: ebook.index.words.count,
      anchored: BookPositionAnchors.estimate(word: excerpt.word, for: context.bookID)
    )

    let opening: String = excerpt.page.bodyWords.prefix(12).joined(separator: " ")
    AppLogger.readAlong.info(
      "Position Sync: reading position is word \(excerpt.word) of \(ebook.index.words.count), audio near \(estimates.map { Int($0.time) })"
    )
    AppLogger.readAlong.info("Position Sync: the passage opens \"\(opening)\"")

    if let best = estimates.first(where: { $0.confidence != .low }) {
      expectedChapter = context.chapters.first { $0.contains(best.time) }?.title
    }

    let chapterStart =
      excerpt.isSectionStart ? ebook.map.matchedTime(forWord: excerpt.word) : nil

    return (excerpt, estimates, chapterStart)
  }

  private func progressHandler() -> @Sendable (String) -> Void {
    { [weak self] step in
      guard let self else { return }
      Task { @MainActor in
        self.advance(to: step)
      }
    }
  }

  private func advance(to step: String) {
    guard case .searching = phase else { return }
    phase = .searching(step)
  }

  @available(iOS 26.0, *)
  private func finish(_ located: PageLocator.Located?) {
    guard let located else {
      phase = .failed(notFound)
      return
    }

    if let ebookWord, located.isExact {
      BookPositionAnchors.record(
        BookPositionAnchors.Anchor(word: ebookWord, time: located.time),
        for: context.bookID
      )
    }

    present(time: snappedToChapter(located.time), isExact: located.isExact)
  }

  private var notFound: String {
    guard let expectedChapter else { return SyncError.notFound.localizedDescription }

    return String(
      localized:
        "Couldn't find your reading position in \(expectedChapter). That part may not be narrated in this recording."
    )
  }

  private func present(time: TimeInterval, isExact: Bool) {
    phase = .result(
      PositionSyncSheet.Model.Result(
        time: time,
        chapterTitle: context.chapters.first { $0.contains(time) }?.title,
        isExact: isExact
      )
    )
    Haptics.impact(.light)
  }

  private func snappedToChapter(_ time: TimeInterval) -> TimeInterval {
    guard isAtSectionStart else { return time }

    guard let chapter = context.chapters.min(by: { abs($0.start - time) < abs($1.start - time) }),
      abs(chapter.start - time) <= Self.chapterSnapWindow
    else {
      return time
    }

    AppLogger.readAlong.info(
      "Position Sync: snapped \(Int(time))s to the start of \(chapter.title) at \(Int(chapter.start))s"
    )
    return chapterEntry(at: chapter.start)
  }

  private func chapterEntry(at start: TimeInterval) -> TimeInterval {
    let rounded = start.rounded(.up)
    let entry = rounded > start ? rounded : start + Self.wholeSecondNudge
    let ceiling =
      context.chapters
      .min { abs($0.start - start) < abs($1.start - start) }?.end ?? context.duration

    return min(entry, max(start, ceiling))
  }

  private var playhead: TimeInterval? {
    guard let player = PlayerManager.shared.current, player.id == context.bookID else { return nil }
    return player.secondsFromStartOfBook
  }
}
