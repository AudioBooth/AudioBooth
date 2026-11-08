import Combine
import Nuke
import SwiftUI

final class BookPosterModel: BookPoster.Model {
  private static var backgroundColors: [URL: Color] = [:]

  private let playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()

  init(book: BookCard.Model) {
    super.init(book: book)

    observePlayer()
    setupBackgroundColor()
  }

  override func onPlayTapped() {
    if let current = playerManager.current, current.id == book.id {
      current.onTogglePlaybackTapped()
    } else {
      book.contextMenu?.onPlayTapped()
    }
  }

  private func observePlayer() {
    playerManager.$current
      .sink { [weak self] current in
        self?.observePlaybackState(current)
      }
      .store(in: &cancellables)
  }

  private func observePlaybackState(_ current: BookPlayer.Model?) {
    guard let current, current.id == book.id else {
      if isPlaying { isPlaying = false }
      return
    }

    isPlaying = current.isPlaying

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self, weak current] in
      Task { @MainActor [weak self, weak current] in
        guard let self, let current, current === self.playerManager.current else { return }
        self.observePlaybackState(current)
      }
    }
  }

  private func setupBackgroundColor() {
    guard let coverURL = book.cover.url else { return }

    if let color = Self.backgroundColors[coverURL] {
      backgroundColor = color
      return
    }

    Task { [weak self] in
      await self?.loadBackgroundColor(coverURL)
    }
  }

  private func loadBackgroundColor(_ coverURL: URL) async {
    let request = ImageRequest(url: coverURL, processors: [.resize(width: 40)])
    guard let image = try? await ImagePipeline.shared.image(for: request),
      let palette = image.coverPalette
    else { return }

    let color = Color(palette.background)
    Self.backgroundColors[coverURL] = color
    backgroundColor = color
  }
}
