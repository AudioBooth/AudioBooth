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

  private var context: PageSyncBookContext
  private let loader = EbookIndexLoader()
  private var playerManager: PlayerManager { .shared }

  private var pageTokens: [String] = []
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

    let tokens = PageTextMatcher.pageTokens(from: lines)
    AppLogger.viewModel.info("Page Sync: scanned \(lines.count) lines, \(tokens.count) words")
    guard tokens.count >= 4 else {
      phase = .failed(PageSyncError.noTextFound.localizedDescription)
      return
    }
    run(tokens: tokens, excerpt: excerpt(from: lines))
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

  private func run(tokens: [String], excerpt: String) {
    processingTask?.cancel()

    processingTask = Task { [weak self] in
      guard let self else { return }
      do {
        phase = .processing(String(localized: "Looking for the ebook…"))
        let loaded = try await loader.load(for: context.book)
        context.ebookBook = loaded.ebookBook
        let index = loaded.index
        try Task.checkCancellation()

        pageTokens = tokens
        phase = .processing(String(localized: "Finding your page…"))
        let match = await Task.detached {
          PageTextMatcher.match(tokens: tokens, in: index)
        }.value
        try Task.checkCancellation()
        guard let match else { throw PageSyncError.pageNotFound }
        AppLogger.viewModel.info(
          "Page Sync: matched \(match.matchedWindows)/\(match.totalWindows) windows at offset \(match.offset)"
        )
        let offset = match.offset

        if let section = index.section(containing: offset) {
          AppLogger.viewModel.info(
            "Page Sync: page is in ebook section \"\(section.title ?? section.href)\"; audio chapters: \(context.audioChapters.prefix(6).map(\.title))…"
          )
        }

        let candidates = AudioPositionEstimator.applyingCalibration(
          context.calibration,
          to: AudioPositionEstimator.candidates(
            offset: offset,
            index: index,
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
          excerpt: excerpt,
          precision: .approximate,
          isRefining: false,
          refiningStatus: nil
        )

        phase = .processing(String(localized: "Listening to the audio…"))
        await locate(candidates, fallback: approximate)
      } catch is CancellationError {
        return
      } catch {
        AppLogger.viewModel.error("Page Sync failed: \(error)")
        phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Transcribes the audio around the candidates until the page is heard. The result is only
  /// shown once it is exact; the estimate is shown as a fallback when nothing matched.
  private func locate(_ candidates: [AudioPositionEstimator.Estimate], fallback: PageSyncSheet.Result) async {
    let sources = context.audioSources
    let tokens = pageTokens
    let locale = context.recognitionLocale
    var result = fallback

    guard !sources.isEmpty else {
      AppLogger.viewModel.warning("Page Sync refinement skipped: no audio sources for \(context.book.id)")
      phase = .result(result)
      return
    }

    guard await SpeechAlignmentRefiner.requestAuthorization() else {
      AppLogger.viewModel.info("Page Sync refinement skipped: speech recognition not authorized")
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
      let located = try await Task.detached {
        try await SpeechAlignmentRefiner.locate(
          candidates: candidates,
          sources: sources,
          pageTokens: tokens,
          locale: locale,
          onProgress: progress.send
        )
      }.value
      guard !Task.isCancelled else { return }

      if let located {
        AppLogger.viewModel.info(
          "Page Sync: refined to \(Int(located.refinement.time))s (confidence \(String(format: "%.2f", located.refinement.confidence)))"
        )
        result.time = located.refinement.time
        result.precision = .exact
        result.chapterTitle = context.chapter(containing: result.time)?.title ?? result.chapterTitle
        if let primary = candidates.first(where: { $0.method != .calibrated }) {
          context.storeCalibration(located.refinement.time - primary.time)
        }
      } else {
        AppLogger.viewModel.info("Page Sync: no speech match in any candidate")
      }
    } catch is CancellationError {
      return
    } catch SpeechAlignmentRefiner.RefinerError.fileTooLarge(let size) {
      AppLogger.viewModel.warning("Page Sync refinement needs the audio downloaded: track is \(size / 1_048_576) MB")
      result.needsDownload = true
    } catch {
      AppLogger.viewModel.warning("Page Sync refinement failed: \(error)")
    }

    guard !Task.isCancelled else { return }
    phase = .result(result)
  }

  /// Bridges progress messages from the refiner's background task to the main actor.
  private final class ProgressRelay: @unchecked Sendable {
    private let handler: @Sendable (String) -> Void

    init(_ handler: @escaping @Sendable (String) -> Void) {
      self.handler = handler
    }

    @Sendable func send(_ message: String) {
      handler(message)
    }
  }

  private func excerpt(from lines: [String]) -> String {
    let joined = PageTextNormalizer.joinLines(lines)
    let words = joined.split(separator: " ").prefix(24)
    return words.joined(separator: " ") + (words.count == 24 ? "…" : "")
  }
}
