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

    let initialState = DownloadManager.shared.downloadState(for: playerModel.bookID)
    self.hasSwitchedToLocal = initialState == .downloaded

    let savedSpeed = BookSpeedPickerModel.savedSpeed
    super.init(hasChapters: hasChapters, downloadState: initialState, speed: savedSpeed)

    let speedPickerModel = BookSpeedPickerModel(playerModel: playerModel)
    speedPickerModel.optionsModel = self
    self.speedPicker = speedPickerModel

    observeDownloadProgress()
  }

  private func observeDownloadProgress() {
    guard let bookID = playerModel?.bookID else { return }

    Publishers.CombineLatest3(
      downloadManager.$currentProgress,
      downloadManager.$activeBookIDs,
      localStorage.$books
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _, _, books in
      guard let self else { return }
      self.downloadState = self.downloadManager.downloadState(for: bookID)

      if self.downloadState == .downloaded, !self.hasSwitchedToLocal,
        let localBook = books.first(where: { $0.id == bookID })
      {
        self.hasSwitchedToLocal = true
        self.playerModel?.switchToLocalPlayback(localBook)
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
    case .notDownloaded, .paused:
      downloadManager.startDownload(for: playerModel.book)
    case .downloading:
      downloadManager.deleteDownload(for: playerModel.bookID)
    case .downloaded:
      removeDownload()
    }

    downloadState = downloadManager.downloadState(for: playerModel.bookID)
  }

  override func onRemoveDownloadTapped() {
    removeDownload()
  }

  private func removeDownload() {
    guard let playerModel else { return }
    downloadManager.deleteDownload(for: playerModel.bookID)
    playerModel.clearLocalPlayback()
    hasSwitchedToLocal = false
    downloadState = .notDownloaded
  }
}
