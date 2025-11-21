import Combine
import Foundation

final class BookPlayerOptionsModel: PlayerOptionsSheet.Model {
  weak var playerModel: BookPlayerModel?

  private let downloadManager = DownloadManager.shared
  private let localStorage = LocalBookStorage.shared
  private var cancellables = Set<AnyCancellable>()
  private var hasSwitchedToLocal = false

  init(playerModel: BookPlayerModel, hasChapters: Bool) {
    self.playerModel = playerModel

    let initialState: DownloadManager.DownloadState
    if let localBook = localStorage.books.first(where: { $0.id == playerModel.bookID }),
      localBook.isDownloaded
    {
      initialState = .downloaded
      self.hasSwitchedToLocal = true
    } else if downloadManager.isDownloading(for: playerModel.bookID) {
      initialState = .downloading(progress: 0)
    } else {
      initialState = .notDownloaded
    }

    super.init(hasChapters: hasChapters, downloadState: initialState)
    observeDownloadProgress()
  }

  private func observeDownloadProgress() {
    guard let playerModel else { return }

    downloadManager.$currentProgress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] progressMap in
        guard let self else { return }
        if let progress = progressMap[playerModel.bookID] {
          self.downloadState = .downloading(progress: progress)
        }
      }
      .store(in: &cancellables)

    localStorage.$books
      .receive(on: DispatchQueue.main)
      .sink { [weak self] books in
        guard let self else { return }
        if let localBook = books.first(where: { $0.id == playerModel.bookID }),
          localBook.isDownloaded
        {
          self.downloadState = .downloaded
          if !self.hasSwitchedToLocal {
            self.hasSwitchedToLocal = true
            playerModel.switchToLocalPlayback(localBook)
          }
        } else if case .downloading = self.downloadState {
        } else {
          self.downloadState = .notDownloaded
        }
      }
      .store(in: &cancellables)
  }

  override func onChaptersTapped() {
    playerModel?.chapters?.isPresented = true
  }

  override func onDownloadTapped() {
    guard let playerModel else { return }

    switch downloadState {
    case .notDownloaded:
      downloadState = .downloading(progress: 0)
      downloadManager.startDownload(for: playerModel.book)
    case .downloading:
      downloadManager.cancelDownload(for: playerModel.bookID)
      downloadState = .notDownloaded
    case .downloaded:
      downloadManager.deleteDownload(for: playerModel.bookID)
      playerModel.clearLocalPlayback()
      hasSwitchedToLocal = false
      downloadState = .notDownloaded
    }
  }
}
