import API
import Combine
import Foundation
import Models

final class ContinueListeningBookCardModel: BookCard.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
  }

  private let item: Item
  private var progressObservation: Task<Void, Never>?
  private var downloadStateCancellable: AnyCancellable?

  var mediaProgress: MediaProgress? {
    didSet {
      progressChanged()
    }
  }

  init(book: Book, onRemoved: @escaping () -> Void) {
    let timeRemaining =
      Duration.seconds(book.duration)
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
      + " remaining"

    self.item = .remote(book)

    super.init(
      id: book.id,
      title: book.title,
      details: timeRemaining,
      cover: Cover.Model(
        url: book.coverURL(),
        title: book.title,
        author: book.authorName,
        progress: MediaProgress.progress(for: book.id)
      ),
      contextMenu: BookCardContextMenuModel(
        book,
        onProgressChanged: nil,
        onRemoveFromContinueListening: onRemoved
      )
    )

    observeMediaProgress()
    setupDownloadProgressObserver()
  }

  init(localBook: LocalBook, onRemoved: @escaping () -> Void) {
    let timeRemaining =
      Duration.seconds(localBook.duration)
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
      + " remaining"

    self.item = .local(localBook)

    super.init(
      id: localBook.bookID,
      title: localBook.title,
      details: timeRemaining,
      cover: Cover.Model(
        url: localBook.coverURL,
        title: localBook.title,
        author: localBook.authorNames,
        progress: MediaProgress.progress(for: localBook.bookID)
      ),
      contextMenu: BookCardContextMenuModel(
        localBook,
        onProgressChanged: nil,
        onRemoveFromContinueListening: onRemoved
      )
    )

    observeMediaProgress()
    setupDownloadProgressObserver()
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
          details =
            Duration.seconds(current.playbackProgress.totalTimeRemaining)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
            + " remaining"
        } else {
          details =
            Duration.seconds(remainingTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
            + " remaining"
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
