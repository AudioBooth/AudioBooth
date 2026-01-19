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

        return DownloadingListView.BookItem(
          id: bookID,
          title: info.title,
          details: info.details,
          coverURL: info.coverURL,
          progress: progress
        )
      }
  }
}
