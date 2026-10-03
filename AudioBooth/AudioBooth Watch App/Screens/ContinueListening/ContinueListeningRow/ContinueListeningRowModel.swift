import Combine
import Foundation

final class ContinueListeningRowModel: ContinueListeningRow.Model {
  let book: WatchBook
  private let playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()

  init(book: WatchBook, showsDownloadStatus: Bool = false) {
    self.book = book

    let timeRemainingText = Self.formatTimeRemaining(book.timeRemaining)

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      timeRemaining: timeRemainingText,
      isDownloaded: LocalBookStorage.shared.books.first { $0.id == book.id }?.isDownloaded ?? false
    )

    if showsDownloadStatus {
      observeDownloadStatus()
    }
  }

  private func observeDownloadStatus() {
    let downloadManager = DownloadManager.shared
    let bookID = book.id

    downloadManager.$currentProgress
      .combineLatest(downloadManager.$activeBookIDs)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _, _ in
        self?.downloadStatus = Self.formatDownloadStatus(downloadManager.downloadState(for: bookID))
      }
      .store(in: &cancellables)
  }

  private static func formatDownloadStatus(_ state: DownloadManager.DownloadState) -> String? {
    switch state {
    case .downloading(let progress):
      return progress.formatted(.percent.precision(.fractionLength(0)))
    case .paused(let progress):
      let percent = progress.formatted(.percent.precision(.fractionLength(0)))
      return String(localized: "Paused \(percent)")
    case .notDownloaded, .downloaded:
      return nil
    }
  }

  private static func formatTimeRemaining(_ timeRemaining: Double) -> String? {
    guard timeRemaining > 0 else { return nil }
    return Duration.seconds(timeRemaining).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }

  override func onTapped() {
    playerManager.open(book)
  }
}
