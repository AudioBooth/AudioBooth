import Audiobookshelf
import Combine
import Models
import SwiftData
import SwiftUI

final class RecentRowModel: RecentRow.Model {
  enum Item {
    case recent(RecentlyPlayedItem)
    case book(Book)
  }

  let item: Item

  private let downloadManager = DownloadManager.shared
  private var playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()
  private var mediaProgressObservation: Task<Void, Never>?

  private var onRemoved: (() -> Void)?

  init(recent: RecentlyPlayedItem) {
    self.item = .recent(recent)

    super.init(
      id: recent.bookID,
      title: recent.title,
      author: recent.author,
      coverURL: recent.coverURL,
      progress: 0,
      lastPlayedAt: nil,
      timeRemaining: nil
    )

    setupDownloadStateBinding()
    setupProgressObservation()
  }

  init(book: Book, onRemoved: @escaping () -> Void) {
    self.item = .book(book)

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      progress: 0,
      lastPlayedAt: nil,
      timeRemaining: nil
    )

    setupDownloadStateBinding()
    setupProgressObservation()

    self.onRemoved = onRemoved
  }

  isolated deinit {
    mediaProgressObservation?.cancel()
  }

  override func onTapped() {
    switch item {
    case .recent(let recentItem):
      PlayerManager.shared.setCurrent(recentItem)
    case .book(let book):
      PlayerManager.shared.setCurrent(book)
    }
  }

  private func setupDownloadStateBinding() {
    downloadManager.$downloads
      .map { [weak self] downloads in
        guard let self = self else { return .notDownloaded }

        if downloads[id] == true {
          return .downloading
        }

        switch self.item {
        case .recent(let recentItem):
          return recentItem.playSessionInfo.isDownloaded ? .downloaded : .notDownloaded
        case .book:
          return .notDownloaded
        }
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)
  }

  private func setupProgressObservation() {
    let id = id
    mediaProgressObservation = Task { [weak self] in
      for await progress in MediaProgress.observe(bookID: id) {
        guard !Task.isCancelled, let self = self, let progress else { continue }
        guard !AppStateManager.shared.isInBackground else { continue }

        self.progress = progress.progress
        self.lastPlayedAt = progress.lastPlayedAt

        switch item {
        case .recent:
          self.timeRemaining = Self.formatTimeRemaining(progress: progress)
        case .book(let book):
          self.timeRemaining = Self.formatTimeRemaining(from: book, progress: progress)
        }
      }
    }
  }

  override func onDownloadTapped() {
    switch downloadState {
    case .downloading:
      downloadManager.cancelDownload(for: id)
    case .downloaded:
      downloadManager.deleteDownload(for: id)
    case .notDownloaded:
      switch item {
      case .recent(let recentItem):
        downloadManager.startDownload(for: recentItem)
      case .book(let book):
        downloadManager.startDownload(for: book)
      }
    }
  }

  override func onDeleteTapped(isFileOnly: Bool) {
    Task {
      do {
        if case .recent(let recent) = item {
          if isFileOnly {
            try recent.deleteFiles()
          } else {
            try recent.delete()
          }
        }

        if !isFileOnly, let progress = try? MediaProgress.fetch(bookID: id), let id = progress.id {
          try? await Audiobookshelf.shared.sessions.removeFromContinueListening(id)
          onRemoved?()
        }
      } catch {
      }
    }
  }

  override func onMarkFinishedTapped(isFinished: Bool) {
    Task {
      do {
        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: id, isFinished: isFinished)

        try MediaProgress.updateFinishedStatus(for: id, isFinished: isFinished)

        if playerManager.current?.id == id {
          playerManager.clearCurrent()
        }
      } catch {
      }
    }
  }

  private static func formatTimeRemaining(progress: MediaProgress) -> String? {
    guard progress.duration > 0 else { return nil }
    let remainingTime = progress.duration - progress.currentTime
    guard remainingTime > 0 else { return nil }
    return Duration.seconds(remainingTime).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }

  private static func formatTimeRemaining(from book: Book, progress: MediaProgress) -> String? {
    guard progress.progress > 0,
      progress.progress < 1.0
    else { return nil }
    let remainingTime = book.duration * (1.0 - progress.progress)
    guard remainingTime > 0 else { return nil }
    return Duration.seconds(remainingTime).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }
}

extension RecentRowModel.Item {
  var id: String {
    switch self {
    case .recent(let recentItem): recentItem.bookID
    case .book(let book): book.id
    }
  }
}
