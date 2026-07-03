import API
import Combine
import Foundation
import Models

final class ContinueListeningBookCardModel: BookCard.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
    case localEpisode(LocalEpisode)
  }

  private var progressObservation: Task<Void, Never>?
  private var downloadStateCancellable: AnyCancellable?

  var mediaProgress: MediaProgress? {
    didSet {
      progressChanged()
    }
  }

  init(book: Book, onRemoved: @escaping () -> Void) {
    super.init(
      id: book.id,
      title: book.title,
      details: nil,
      cover: Cover.Model(
        url: book.coverURL(),
        title: book.title,
        author: book.authorName,
        progress: MediaProgress.progress(for: book.id)
      ),
      author: book.authorName,
      contextMenu: BookCardContextMenuModel(
        book,
        onProgressChanged: nil,
        onRemoveFromContinueListening: onRemoved
      ),
      hasEbook: book.media.ebookFile != nil || book.media.ebookFormat != nil,
      isExplicit: book.media.metadata.explicit ?? false,
      timeRemaining: book.duration
    )

    observeMediaProgress()
    setupDownloadProgressObserver()
  }

  init(localBook: LocalBook, onRemoved: @escaping () -> Void) {
    super.init(
      id: localBook.bookID,
      title: localBook.title,
      details: nil,
      cover: Cover.Model(
        url: localBook.coverURL,
        title: localBook.title,
        author: localBook.authorNames,
        progress: MediaProgress.progress(for: localBook.bookID)
      ),
      author: localBook.authorNames,
      contextMenu: BookCardContextMenuModel(
        localBook,
        onProgressChanged: nil,
        onRemoveFromContinueListening: onRemoved
      ),
      hasEbook: localBook.mediaType.contains(.ebook),
      isExplicit: localBook.isExplicit,
      timeRemaining: localBook.duration
    )

    observeMediaProgress()
    setupDownloadProgressObserver()
  }

  init(localEpisode episode: LocalEpisode) {
    super.init(
      id: episode.episodeID,
      podcastID: episode.podcast?.podcastID,
      title: episode.title,
      details: nil,
      cover: Cover.Model(
        url: episode.coverURL,
        title: episode.title,
        author: episode.podcast?.author,
        progress: MediaProgress.progress(for: episode.episodeID)
      ),
      author: episode.podcast?.author,
      timeRemaining: episode.duration
    )

    observeMediaProgress()
  }

  override func onAppear() {
    mediaProgress = try? MediaProgress.fetch(bookID: id)
  }

  private func observeMediaProgress() {
    let bookID = id
    progressObservation = Task { [weak self] in
      for await mediaProgress in MediaProgress.observe(where: \.bookID, equals: bookID) {
        self?.mediaProgress = mediaProgress
      }
    }
  }

  private func setupDownloadProgressObserver() {
    downloadStateCancellable = DownloadManager.shared.$downloadStates
      .sink { [weak self] states in
        guard let self else { return }
        if case .downloading(let progress) = states[self.id] {
          self.cover.downloadProgress = progress
        } else {
          self.cover.downloadProgress = nil
        }
        self.isDownloaded = states[self.id] == .downloaded
      }
  }
}

extension ContinueListeningBookCardModel {
  func progressChanged() {
    guard let mediaProgress else { return }

    Task { @MainActor in
      cover.progress = MediaProgress.progress(for: mediaProgress.bookID)

      let remainingTime = mediaProgress.remaining
      if remainingTime > 0 && mediaProgress.progress > 0 {
        if let current = PlayerManager.shared.current,
          [id].contains(current.id)
        {
          timeRemaining = current.playbackProgress.totalTimeRemaining
        } else {
          timeRemaining = remainingTime
        }
      }
    }
  }
}

@MainActor
extension ContinueListeningBookCardModel: Comparable {
  static func < (lhs: ContinueListeningBookCardModel, rhs: ContinueListeningBookCardModel) -> Bool {
    switch (lhs.mediaProgress?.lastPlayedAt, rhs.mediaProgress?.lastPlayedAt) {
    case let (.some(l), .some(r)): l > r
    case (.some(_), nil): true
    case (nil, _): false
    }
  }

  static func == (lhs: ContinueListeningBookCardModel, rhs: ContinueListeningBookCardModel) -> Bool {
    lhs.id == rhs.id
  }
}
