import Audiobookshelf
import Combine
import SwiftData
import SwiftUI

@MainActor
final class RecentRowModel: RecentRow.Model {
  private var userProgressService = UserProgressService.shared

  enum Item {
    case recent(RecentlyPlayedItem)
    case book(Book)
  }

  let item: Item
  let lastPlayedAt: Date?

  private let downloadManager = DownloadManager.shared
  private var playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()

  private var onRemoved: (() -> Void)?

  init(recent: RecentlyPlayedItem) {
    self.item = .recent(recent)
    self.lastPlayedAt = recent.lastPlayedAt

    super.init(
      id: recent.bookID,
      title: recent.title,
      author: recent.author,
      coverURL: recent.coverURL,
      progress: recent.progress,
      lastPlayed: recent.lastPlayedAt.formatted(.relative(presentation: .named)),
      timeRemaining: Self.formatTimeRemaining(from: recent)
    )

    setupDownloadStateBinding()
  }

  init(book: Book, onRemoved: @escaping () -> Void) {
    self.item = .book(book)

    let progress = userProgressService.progressByBookID[book.id]

    self.lastPlayedAt = progress.map {
      Date(timeIntervalSince1970: TimeInterval($0.lastUpdate / 1000))
    }

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      progress: progress?.progress,
      lastPlayed: lastPlayedAt?.formatted(.relative(presentation: .named)),
      timeRemaining: Self.formatTimeRemaining(from: book, progress: progress?.progress)
    )

    setupDownloadStateBinding()

    self.onRemoved = onRemoved
  }

  @MainActor
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

        if let managerState = downloads[id] {
          return managerState
        }

        switch self.item {
        case .recent(let recentItem):
          return recentItem.playSessionInfo.isDownloaded ? .downloaded : .notDownloaded
        case .book:
          return .notDownloaded
        }
      }
      .assign(to: \.downloadState, on: self)
      .store(in: &cancellables)
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

        if !isFileOnly, let progress = userProgressService.progressByBookID[id] {
          try? await Audiobookshelf.shared.sessions.removeFromContinueListening(progress.id)
          onRemoved?()
        }
      } catch {
        print("Failed to delete item: \(error)")
      }
    }
  }

  private static func formatTimeRemaining(from recent: RecentlyPlayedItem) -> String? {
    guard let duration = recent.duration, duration > 0 else { return nil }
    let remainingTime = duration - recent.currentTime
    guard remainingTime > 0 else { return nil }
    return Duration.seconds(remainingTime).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }

  private static func formatTimeRemaining(from book: Book, progress: Double?) -> String? {
    guard let progress = progress, progress > 0, progress < 1.0 else { return nil }
    let remainingTime = book.duration * (1.0 - progress)
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
