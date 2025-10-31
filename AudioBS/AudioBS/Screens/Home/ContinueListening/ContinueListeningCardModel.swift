import API
import Combine
import Foundation
import Models

final class ContinueListeningCardModel: ContinueListeningCard.Model {
  private let book: Book
  private var onRemoved: (() -> Void)?
  private var cancellables = Set<AnyCancellable>()

  init(book: Book, onRemoved: @escaping () -> Void) {
    self.book = book

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      progress: 0,
      lastPlayedAt: nil,
      timeRemaining: nil
    )

    self.onRemoved = onRemoved
    observePlayerChanges()
  }

  override func onAppear() {
    fetchProgressData()
  }

  private func observePlayerChanges() {
    PlayerManager.shared.$current
      .receive(on: DispatchQueue.main)
      .sink { [weak self] current in
        guard let self else { return }
        self.observeIsPlaying(current)
      }
      .store(in: &cancellables)
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.id == id else { return }

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updateLastPlayedStatus()
        self.observeIsPlaying(PlayerManager.shared.current)
      }
    }
  }

  private func updateLastPlayedStatus() {
    let current = PlayerManager.shared.current

    if let current, current.id == id, current.isPlaying {
      lastPlayedAt = .distantFuture
    } else if let mediaProgress = try? MediaProgress.fetch(bookID: id) {
      lastPlayedAt = mediaProgress.lastPlayedAt
    }
  }

  private func fetchProgressData() {
    guard let mediaProgress = try? MediaProgress.fetch(bookID: id) else { return }

    progress = mediaProgress.progress

    if let current = PlayerManager.shared.current, current.id == id, current.isPlaying {
      lastPlayedAt = .distantFuture
    } else {
      lastPlayedAt = mediaProgress.lastPlayedAt
    }

    timeRemaining = Self.formatTimeRemaining(from: book, progress: mediaProgress)
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
