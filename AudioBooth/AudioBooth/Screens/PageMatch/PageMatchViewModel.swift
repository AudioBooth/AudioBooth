import Combine
import Foundation
import Logging
import Models
import PhotosUI
import SwiftUI
import UIKit

final class PageMatchViewModel: PageMatchSheet.Model {
  enum SyncError: LocalizedError {
    case notEnoughText
    case notFound

    var errorDescription: String? {
      switch self {
      case .notEnoughText:
        String(localized: "Not enough readable text. Try again with more light and the page flat.")
      case .notFound:
        String(
          localized:
            "Couldn't find that page in the audiobook. Try a page with more text, or one closer to where you are listening."
        )
      }
    }
  }

  private static let ebookQueryWords = 80
  private static let ebookAlignmentScore = 0.45
  private static let ebookAnchorScore = 0.7

  private let context: PageMatchBookContext
  private let ebooks = EbookTextIndexLoader()
  private var search: Task<Void, Never>?
  private var reading: Task<Void, Never>?
  private var ebookWord: Int?
  private var ebookWords: NarrationWordIndex?

  init(context: PageMatchBookContext) {
    self.context = context
    super.init()

    scanLanguages = PageScannerView.supportedLanguages(
      from: context.languageCode.map { [$0] } ?? Array(Locale.preferredLanguages.prefix(2))
    )
    describeReadiness()
  }

  isolated deinit {
    search?.cancel()
    reading?.cancel()
  }

  override func onScanTapped() {
    phase = .idle
    isScannerPresented = true
  }

  override func onChoosePhotoTapped() {
    phase = .idle
    isPhotoPickerPresented = true
  }

  override func onPhotoPicked() {
    guard let photo else { return }

    reading?.cancel()
    phase = .searching(String(localized: "Reading the photo…"))

    let languages = scanLanguages
    reading = Task { [weak self] in
      await self?.readPhoto(photo, languages: languages)
    }
  }

  override func onPageCaptured(_ image: UIImage) {
    isScannerPresented = false
    reading?.cancel()
    phase = .searching(String(localized: "Reading the page…"))

    let languages = scanLanguages
    reading = Task { [weak self] in
      await self?.read(image, languages: languages)
    }
  }

  private func readPhoto(_ photo: PhotosPickerItem, languages: [String]) async {
    do {
      guard let data = try await photo.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      else {
        throw PagePhotoReader.ReaderError.unreadable
      }

      self.photo = nil
      await read(image, languages: languages)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      AppLogger.readAlong.error("Page Match: photo could not be read: \(error)")
      self.photo = nil
      phase = .failed(error.localizedDescription)
    }
  }

  private func read(_ image: UIImage, languages: [String]) async {
    do {
      let lines = try await PagePhotoReader.lines(in: image, languages: languages)
      guard !Task.isCancelled else { return }
      onPageScanned(lines)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      AppLogger.readAlong.error("Page Match: page could not be read: \(error)")
      phase = .failed(error.localizedDescription)
    }
  }

  override func onScanCancelled() {
    isScannerPresented = false
  }

  override func onCancelTapped() {
    search?.cancel()
    search = nil
    reading?.cancel()
    reading = nil
    phase = .idle
  }

  override func onDismiss() {
    search?.cancel()
    search = nil
    reading?.cancel()
    reading = nil
    onFinished?()
  }

  private func onPageScanned(_ lines: [String]) {

    let page = ScannedPage.parse(lines: lines)
    let header: String = page.header ?? "none"
    let number: String = page.pageNumber.map { "\($0)" } ?? "none"
    let opening: String = page.bodyWords.prefix(20).joined(separator: " ")
    AppLogger.readAlong.info(
      "Page Match: scanned \(lines.count) lines, \(page.bodyWords.count) words, header \(header), page number \(number)"
    )
    AppLogger.readAlong.info("Page Match: page opens \"\(opening)\"")

    guard page.isUsable else {
      phase = .failed(SyncError.notEnoughText.localizedDescription)
      return
    }

    start(page)
  }

  override func onPlayTapped() {
    guard case .result(let result) = phase else { return }

    guard let player = PlayerManager.shared.current as? BookPlayerModel,
      player.id == context.bookID
    else {
      Toast(error: String(localized: "Open this audiobook in the player first.")).show()
      return
    }

    player.seekToTime(result.time)
    PlayerManager.shared.play()
    Haptics.impact(.medium)
    onFinished?()
  }

  private func start(_ page: ScannedPage) {
    guard #available(iOS 26.0, *) else {
      phase = .failed(String(localized: "Page Match needs iOS 26 or later."))
      return
    }

    guard let source = context.source else {
      phase = .failed(String(localized: "Download this audiobook to use Page Match."))
      return
    }

    search?.cancel()
    ebookWord = nil
    ebookWords = nil
    phase = .searching(String(localized: "Preparing speech recognition…"))

    search = Task { [weak self] in
      await self?.runSearch(page: page, source: source)
    }
  }

  private func searchWindows(
    for page: ScannedPage,
    ebookEstimates: [AudioPositionEstimator.Estimate]
  ) -> [AudioSearchWindow] {
    var estimate: TimeInterval?
    if let number = page.pageNumber {
      estimate = PageMatchAnchors.estimate(page: number, for: context.bookID)
    }

    return PageSearchPlan.windows(
      for: page,
      chapters: context.chapters,
      duration: context.duration,
      playhead: playhead,
      estimatedTime: estimate,
      ebookEstimates: ebookEstimates
    )
  }

  private func ebookEstimates(for page: ScannedPage) async -> [AudioPositionEstimator.Estimate] {
    guard let url = context.ebookURL else { return [] }

    phase = .searching(String(localized: "Looking for your page in the ebook…"))
    let ebook = await ebooks.load(
      bookID: context.bookID,
      url: url,
      chapters: context.chapters,
      duration: context.duration
    )
    guard let ebook, !Task.isCancelled else { return [] }

    var aligner = TranscriptAligner(words: ebook.index.words)
    aligner.minimumScore = Self.ebookAlignmentScore

    let query = Array(page.bodyWords.prefix(Self.ebookQueryWords))
    guard let alignment = aligner.align(query: query, expectedStart: nil),
      let anchor = alignment.words.first
    else {
      AppLogger.readAlong.info("Page Match: the page could not be placed in the ebook")
      return []
    }

    let word = max(0, anchor.bookWord - anchor.queryIndex)
    ebookWord = alignment.score >= Self.ebookAnchorScore ? word : nil
    ebookWords = ebookWord == nil ? nil : ebook.index.words

    let estimates = AudioPositionEstimator.estimates(
      forWord: word,
      map: ebook.map,
      chapters: context.chapters,
      duration: context.duration,
      totalWords: ebook.index.words.count,
      anchored: BookPositionAnchors.estimate(word: word, for: context.bookID)
    )

    let quality: String = String(format: "%.2f", alignment.score)
    AppLogger.readAlong.info(
      "Page Match: the page is word \(word) of \(ebook.index.words.count) in the ebook (match \(quality)), audio near \(estimates.map { Int($0.time) })"
    )
    return estimates
  }

  @available(iOS 26.0, *)
  private func runSearch(page: ScannedPage, source: NarrationSource) async {
    do {
      let locale = try await ReadAlongAvailability.prepare(preferred: context.locale)
      try Task.checkCancellation()

      let windows = searchWindows(for: page, ebookEstimates: await ebookEstimates(for: page))
      try Task.checkCancellation()

      guard !windows.isEmpty else {
        phase = .failed(SyncError.notFound.localizedDescription)
        return
      }

      let first: String = windows[0].chapterTitle ?? "the whole book"
      AppLogger.readAlong.info(
        "Page Match: searching \(windows.count) window(s), first is \(first)"
      )
      phase = .searching(String(localized: "Listening to the audiobook…"))

      let located = try await PageLocator.locate(
        page: page,
        windows: windows,
        duration: context.duration,
        guide: homingGuide(),
        source: source,
        locale: locale,
        onProgress: progressHandler()
      )
      try Task.checkCancellation()

      finish(located, page: page)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      AppLogger.readAlong.error("Page Match failed: \(error)")
      phase = .failed(error.localizedDescription)
    }
  }

  @available(iOS 26.0, *)
  private func homingGuide() -> PageLocator.Guide? {
    guard let ebookWord, let ebookWords, !ebookWords.isEmpty, context.duration > 0 else {
      return nil
    }

    return PageLocator.Guide(
      ebookWords: ebookWords,
      targetWord: ebookWord,
      wordsPerSecond: Double(ebookWords.count) / context.duration
    )
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
  private func finish(_ located: PageLocator.Located?, page: ScannedPage) {
    guard let located else {
      phase = .failed(SyncError.notFound.localizedDescription)
      return
    }

    if let ebookWord, located.isExact {
      BookPositionAnchors.record(
        BookPositionAnchors.Anchor(word: ebookWord, time: located.time),
        for: context.bookID
      )
    }

    if let number = page.pageNumber, located.isExact {
      PageMatchAnchors.record(
        PageMatchAnchors.Anchor(
          page: number,
          time: located.time,
          secondsPerPage: located.pageSeconds
        ),
        for: context.bookID
      )
    }

    phase = .result(
      PageMatchSheet.Model.Result(
        time: located.time,
        chapterTitle: context.chapters.first { $0.contains(located.time) }?.title,
        isExact: located.isExact
      )
    )
    Haptics.impact(.light)
  }

  private var playhead: TimeInterval? {
    guard let player = PlayerManager.shared.current, player.id == context.bookID else { return nil }
    return player.secondsFromStartOfBook
  }

  private func describeReadiness() {
    guard #available(iOS 26.0, *) else {
      canScan = false
      canChoosePhoto = false
      explanation = String(localized: "Page Match needs iOS 26 or later.")
      return
    }

    guard context.isDownloaded else {
      canScan = false
      canChoosePhoto = false
      explanation = String(
        localized: "Download this audiobook first. Page Match listens to the audio on your device."
      )
      return
    }

    canChoosePhoto = true
    canScan = PageScannerView.isSupported

    explanation =
      canScan
      ? String(
        localized:
          "Point the camera at the page you're reading, or pick a photo of one you took earlier. AudioBooth listens to the audiobook to find the same words, starting from where you are now."
      )
      : String(
        localized:
          "Pick a photo of the page you're reading. AudioBooth listens to the audiobook to find the same words, starting from where you are now."
      )
  }
}
