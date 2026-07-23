import Combine
import Foundation
import Models

final class DownloadingListViewModel: DownloadingListView.Model {
  private var downloadManager: DownloadManager { .shared }
  private var cancellables: Set<AnyCancellable> = []
  private var requestsObservation: Task<Void, Never>?

  private struct PendingDownload {
    let itemID: String
    let kind: DownloadRequest.Kind
    let podcastID: String?
    let title: String
    let coverURL: URL?
    let duration: TimeInterval
    let size: Int64
    let createdAt: Date
    let hasFailed: Bool
  }

  private var pending: [PendingDownload] = []
  private var activeIDs: Set<String> = []

  override init(books: [DownloadingListView.BookItem] = []) {
    super.init(books: books)

    requestsObservation = Task { [weak self] in
      for await requests in DownloadRequest.observeAll() {
        guard let self else { return }
        self.pending = requests.sorted().map {
          PendingDownload(
            itemID: $0.itemID,
            kind: $0.kind,
            podcastID: $0.podcastID,
            title: $0.title,
            coverURL: $0.coverURL,
            duration: $0.duration,
            size: $0.size,
            createdAt: $0.createdAt,
            hasFailed: $0.hasFailed
          )
        }
        self.rebuild(states: self.downloadManager.downloadStates)
      }
    }

    downloadManager.$downloadStates
      .sink { [weak self] states in
        self?.apply(states: states)
      }
      .store(in: &cancellables)
  }

  override func onCancelDownload(bookID: String) {
    downloadManager.cancelDownload(for: bookID)
  }

  override func onResumeDownload(bookID: String) {
    guard let request = try? DownloadRequest.fetch(itemID: bookID) else { return }
    request.failureCount = 0
    try? request.save()
    downloadManager.resumeDownload(request)
  }

  override func onRemoveDownload(bookID: String) {
    guard let download = pending.first(where: { $0.itemID == bookID }) else { return }

    switch download.kind {
    case .episode:
      guard let podcastID = download.podcastID else { return }
      downloadManager.deleteEpisodeDownload(episodeID: bookID, podcastID: podcastID)
    case .ebook:
      downloadManager.deleteEbookDownload(for: bookID)
    case .book:
      downloadManager.deleteDownload(for: bookID)
    }
  }

  private func apply(states: [String: DownloadManager.DownloadState]) {
    if activeSet(from: states) == activeIDs {
      updateProgress(states: states)
    } else {
      rebuild(states: states)
    }
  }

  private func activeSet(from states: [String: DownloadManager.DownloadState]) -> Set<String> {
    Set(
      states.compactMap { key, value in
        if case .downloading = value { return key } else { return nil }
      }
    )
  }

  private func updateProgress(states: [String: DownloadManager.DownloadState]) {
    for index in books.indices {
      guard case .downloading(let progress) = states[books[index].id] else { continue }
      books[index].progress = progress
      books[index].status = .downloading
      books[index].details = detailsText(
        duration: books[index].duration,
        totalSize: books[index].totalSize,
        progress: progress
      )
    }
  }

  private func rebuild(states: [String: DownloadManager.DownloadState]) {
    activeIDs = activeSet(from: states)

    books =
      pending
      .filter { $0.kind == .ebook || states[$0.itemID] != .downloaded }
      .map { download in
        let status: DownloadingListView.BookItem.Status
        let progress: Double
        if case .downloading(let value) = states[download.itemID] {
          status = .downloading
          progress = value
        } else {
          status = download.hasFailed ? .failed : .queued
          progress = downloadManager.downloadedFraction(
            itemID: download.itemID,
            kind: download.kind,
            podcastID: download.podcastID,
            size: download.size
          )
        }

        return DownloadingListView.BookItem(
          id: download.itemID,
          title: download.title,
          details: detailsText(
            duration: download.duration,
            totalSize: download.size,
            progress: progress
          ),
          coverURL: download.coverURL,
          duration: download.duration,
          totalSize: download.size,
          progress: progress,
          status: status
        )
      }
  }

  private func detailsText(duration: TimeInterval, totalSize: Int64, progress: Double?) -> String? {
    var parts: [String] = []
    if duration > 0 {
      parts.append(
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
      )
    }
    if totalSize > 0 {
      let totalText = totalSize.formatted(.byteCount(style: .file))
      if let progress {
        let currentBytes = Int64(Double(totalSize) * progress)
        let currentText = currentBytes.formatted(.byteCount(style: .file))
        parts.append("\(currentText) of \(totalText)")
      } else {
        parts.append(totalText)
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
  }
}
