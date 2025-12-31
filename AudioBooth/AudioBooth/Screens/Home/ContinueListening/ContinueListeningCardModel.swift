import API
import Combine
import Foundation
import Models

final class ContinueListeningCardModel: ContinueListeningCard.Model {
  private var onRemoved: (() -> Void)?
  private var cancellables = Set<AnyCancellable>()

  private var progressObservation: Task<Void, Never>?

  var mediaProgress: MediaProgress? {
    didSet {
      progressChanged()
    }
  }

  init(book: Book, onRemoved: @escaping () -> Void) {
    let timeRemaining = Duration.seconds(book.duration)
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow))

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL(),
      progress: MediaProgress.progress(for: book.id),
      timeRemaining: timeRemaining
    )

    self.onRemoved = onRemoved
    observeMediaProgress()
  }

  init(localBook: LocalBook, onRemoved: @escaping () -> Void) {
    let timeRemaining = Duration.seconds(localBook.duration)
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow))

    super.init(
      id: localBook.bookID,
      title: localBook.title,
      author: localBook.authorNames,
      coverURL: localBook.coverURL,
      progress: MediaProgress.progress(for: localBook.bookID),
      timeRemaining: timeRemaining
    )

    self.onRemoved = onRemoved
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

  override func onRemoveFromListTapped() {
    guard
      let progress = try? MediaProgress.fetch(bookID: id),
      let id = progress.id
    else { return }

    Task {
      try? await Audiobookshelf.shared.sessions.removeFromContinueListening(id)
      onRemoved?()
    }
  }
}

extension ContinueListeningCardModel {
  func progressChanged() {
    guard let mediaProgress else { return }

    Task { @MainActor in
      progress = mediaProgress.progress

      let remainingTime = mediaProgress.remaining
      if remainingTime > 0 && mediaProgress.progress > 0 {
        if let current = PlayerManager.shared.current,
          [id].contains(current.id)
        {
          timeRemaining = Duration.seconds(current.playbackProgress.totalTimeRemaining)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        } else {
          timeRemaining = Duration.seconds(remainingTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
      }
    }
  }
}

@MainActor
extension ContinueListeningCardModel: Comparable {
  static func < (lhs: ContinueListeningCardModel, rhs: ContinueListeningCardModel) -> Bool {
    switch (lhs.mediaProgress?.lastPlayedAt, rhs.mediaProgress?.lastPlayedAt) {
    case let (.some(l), .some(r)): l > r
    case (.some(_), nil): true
    case (nil, _): false
    }
  }

  static func == (lhs: ContinueListeningCardModel, rhs: ContinueListeningCardModel) -> Bool {
    lhs.id == rhs.id
  }
}
