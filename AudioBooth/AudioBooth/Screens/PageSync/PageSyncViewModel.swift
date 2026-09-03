import API
import Foundation
import Logging
import Models
import UIKit

final class PageSyncViewModel: PageSyncSheet.Model {
  enum PageSyncError: LocalizedError {
    case noTextFound
    case pageNotFound

    var errorDescription: String? {
      switch self {
      case .noTextFound:
        String(localized: "Not enough readable text. Try again with more light and keep the page flat.")
      case .pageNotFound:
        String(localized: "This page could not be matched to the ebook. Try scanning a page with more text.")
      }
    }
  }

  /// Words from the page that are aligned against the book.
  private static let maximumPageWords = 120

  private var context: PageSyncBookContext
  private let loader = EbookIndexLoader()
  private var playerManager: PlayerManager { .shared }
  private var processingTask: Task<Void, Never>?

  init(book: Book, localBook: LocalBook?) {
    self.context = PageSyncBookContext(book: book, localBook: localBook)
    super.init(bookTitle: book.title)
    isScannerSupported = PageScannerView.isSupported
    scanLanguages = context.recognitionLanguages
  }

  isolated deinit {
    processingTask?.cancel()
  }

  override func onPageScanned(_ lines: [String]) {
    isScannerPresented = false
    processingTask?.cancel()

    let tokens = PageWords.tokens(from: lines)
    AppLogger.viewModel.info("Page Sync: scanned \(lines.count) lines, \(tokens.count) words")
    guard tokens.count >= 4 else {
      phase = .failed(PageSyncError.noTextFound.localizedDescription)
      return
    }
    run(tokens: Array(tokens.prefix(Self.maximumPageWords)))
  }

  override func onPlayTapped() {
    guard case .result(let result) = phase else { return }
    processingTask?.cancel()

    if playerManager.current?.id != context.book.id {
      if let localBook = context.localBook, localBook.mediaType.contains(.audiobook) {
        playerManager.setCurrent(localBook)
      } else {
        playerManager.setCurrent(context.book)
      }
    }

    guard let player = playerManager.current as? BookPlayerModel else {
      Toast(error: "Unable to open the player").show()
      return
    }

    player.seekToTime(result.time)
    playerManager.play()
    Haptics.impact(.medium)
    onFinished?()
  }

  override func onDownloadTapped() {
    guard case .result(var result) = phase else { return }
    if let localBook = context.localBook {
      DownloadManager.shared.startDownload(localBook)
    } else {
      DownloadManager.shared.startDownload(context.book)
    }
    result.isDownloading = true
    phase = .result(result)
    Toast(message: "Downloading \(context.book.title)").show()
  }

  override func onRetryTapped() {
    processingTask?.cancel()
    super.onRetryTapped()
  }

  override func onDismiss() {
    processingTask?.cancel()
    onFinished?()
  }

  // MARK: - Pipeline

  private func run(tokens: [String]) {
    processingTask?.cancel()

    processingTask = Task { [weak self] in
      guard let self else { return }
      do {
        phase = .processing(String(localized: "Looking for the ebook…"))
        let loaded = try await loader.load(for: context.book)
        context.ebookBook = loaded.ebookBook
        try Task.checkCancellation()

        phase = .processing(String(localized: "Finding your page…"))
        let index = loaded.index
        let alignment = await Task.detached {
          TranscriptAligner(words: index.words).align(query: tokens, expectedStart: nil)
        }.value
        try Task.checkCancellation()

        guard let alignment, let anchor = alignment.words.first else { throw PageSyncError.pageNotFound }
        // The first aligned word may not be the page's first word; back up by its position.
        let pageWord = max(0, anchor.bookWord - anchor.queryIndex)
        AppLogger.viewModel.info(
          "Page Sync: page starts at book word \(pageWord) of \(index.words.count) (score \(String(format: "%.2f", alignment.score)))"
        )

        let sections = loaded.sections
        if let section = sections.section(containing: pageWord) {
          AppLogger.viewModel.info(
            "Page Sync: page is in ebook section \"\(section.title ?? section.href)\"; audio chapters: \(context.audioChapters.prefix(6).map(\.title))…"
          )
        }

        let candidates = AudioPositionEstimator.applyingCalibration(
          context.calibration,
          to: AudioPositionEstimator.candidates(
            offset: pageWord,
            index: sections,
            chapters: context.audioChapters,
            duration: context.audioDuration
          ),
          chapters: context.audioChapters,
          duration: context.audioDuration
        )
        let estimate = candidates[0]
        AppLogger.viewModel.info(
          "Page Sync: estimated \(Int(estimate.time))s using \(String(describing: estimate.method)); candidates \(candidates.map { Int($0.time) })"
        )

        let approximate = PageSyncSheet.Result(
          time: estimate.time,
          chapterTitle: estimate.chapterTitle,
          excerpt: index.excerpt(startingAtWord: pageWord),
          precision: .approximate,
          isRefining: false,
          refiningStatus: nil
        )

        await locate(pageWord: pageWord, candidates: candidates, index: index, fallback: approximate)
      } catch is CancellationError {
        return
      } catch {
        AppLogger.viewModel.error("Page Sync failed: \(error)")
        phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Listens to the audio around the candidates until the page is heard. The result is only
  /// shown once it is exact; the estimate is the fallback when nothing matched.
  private func locate(
    pageWord: Int,
    candidates: [AudioPositionEstimator.Estimate],
    index: BookTextIndex,
    fallback: PageSyncSheet.Result
  ) async {
    var result = fallback

    guard #available(iOS 26.0, *) else {
      AppLogger.viewModel.info("Page Sync: exact positioning needs iOS 26; showing the estimate")
      phase = .result(result)
      return
    }

    guard let source = context.narrationSource else {
      AppLogger.viewModel.info("Page Sync: audiobook not downloaded; showing the estimate")
      result.needsDownload = true
      phase = .result(result)
      return
    }

    let progress = ProgressRelay { [weak self] message in
      Task { @MainActor in
        guard let self, case .processing = self.phase else { return }
        self.phase = .processing(message)
      }
    }

    do {
      phase = .processing(String(localized: "Preparing speech recognition…"))
      let locale = try await ReadAlongAvailability.prepare(preferred: context.recognitionLocale) { fraction in
        progress.send(String(localized: "Downloading speech model… \(Int(fraction * 100))%"))
      }
      phase = .processing(String(localized: "Listening to the audio…"))

      let duration = context.audioDuration
      let located = try await Task.detached {
        try await PageLocator.locate(
          pageWord: pageWord,
          candidates: candidates,
          index: index,
          source: source,
          locale: locale,
          duration: duration,
          onProgress: progress.send
        )
      }.value
      guard !Task.isCancelled else { return }

      if let located {
        result.time = located.time
        result.precision = .exact
        result.chapterTitle = context.chapter(containing: located.time)?.title ?? result.chapterTitle
        if let primary = candidates.first(where: { $0.method != .calibrated }) {
          context.storeCalibration(located.time - primary.time)
        }
      } else {
        AppLogger.viewModel.info("Page Sync: page not heard near any candidate; showing the estimate")
      }
    } catch is CancellationError {
      return
    } catch {
      AppLogger.viewModel.warning("Page Sync refinement failed: \(error)")
      Toast(error: error.localizedDescription).show()
    }

    guard !Task.isCancelled else { return }
    phase = .result(result)
  }

  /// Bridges progress messages from the locator's background task to the main actor.
  private final class ProgressRelay: @unchecked Sendable {
    private let handler: @Sendable (String) -> Void

    init(_ handler: @escaping @Sendable (String) -> Void) {
      self.handler = handler
    }

    @Sendable func send(_ message: String) {
      handler(message)
    }
  }
}
