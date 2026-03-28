import Combine
import Foundation

final class DownloadingListViewModel: DownloadingListView.Model {
  private var downloadManager: DownloadManager { .shared }
  private var cancellables: Set<AnyCancellable> = []

  override func onAppear() {
    downloadManager.$downloadStates
      .combineLatest(downloadManager.$downloadInfos)
      .sink { [weak self] states, infos in
        self?.rebuildBooks(states: states, infos: infos)
      }
      .store(in: &cancellables)
  }

  override func onCancelDownload(bookID: String) {
    downloadManager.cancelDownload(for: bookID)
  }

  private func rebuildBooks(
    states: [String: DownloadManager.DownloadState],
    infos: [String: DownloadManager.DownloadInfo]
  ) {
    books =
      infos
      .sorted { $0.value.startedAt < $1.value.startedAt }
      .compactMap { bookID, info -> DownloadingListView.BookItem? in
        guard case .downloading(let progress) = states[bookID] else {
          return nil
        }

        var parts: [String] = []
        if let duration = info.duration, duration > 0 {
          parts.append(
            Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
          )
        }
        if let totalSize = info.size {
          let currentBytes = Int64(Double(totalSize) * progress)
          let currentText = currentBytes.formatted(.byteCount(style: .file))
          let totalText = totalSize.formatted(.byteCount(style: .file))
          parts.append("\(currentText) of \(totalText)")
        }

        return DownloadingListView.BookItem(
          id: bookID,
          title: info.title,
          details: parts.isEmpty ? nil : parts.joined(separator: " • "),
          coverURL: info.coverURL,
          progress: progress
        )
      }
  }
}
