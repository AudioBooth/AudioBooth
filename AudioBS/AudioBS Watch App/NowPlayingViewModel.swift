import Combine
import Foundation

final class NowPlayingViewModel: NowPlayingView.Model {
  private var cancellables = Set<AnyCancellable>()
  private let connectivityManager = WatchConnectivityManager.shared
  private let playerManager = PlayerManager.shared

  override init(
    isPlaying: Bool = false,
    progress: Double = 0,
    current: Double = 0,
    remaining: Double = 0,
    total: Double = 0,
    totalTimeRemaining: Double = 0,
    bookID: String = "",
    title: String = "",
    author: String = "",
    coverURL: URL? = nil,
    playbackSpeed: Float = 1.0,
    hasActivePlayer: Bool = false
  ) {
    super.init(
      isPlaying: isPlaying,
      progress: progress,
      current: current,
      remaining: remaining,
      total: total,
      totalTimeRemaining: totalTimeRemaining,
      bookID: bookID,
      title: title,
      author: author,
      coverURL: coverURL,
      playbackSpeed: playbackSpeed,
      hasActivePlayer: hasActivePlayer
    )
    setupBindings()
  }

  private func setupBindings() {
    playerManager.$current
      .sink { [weak self] currentPlayer in
        guard let self = self else { return }

        if let player = currentPlayer {
          self.setupLocalPlayerBindings(player)
          self.hasActivePlayer = true
        } else {
          self.setupRemotePlayerBindings()
        }
      }
      .store(in: &cancellables)
  }

  private func setupLocalPlayerBindings(_ player: BookPlayerModel) {
    cancellables.removeAll()

    player.$isPlaying
      .assign(to: \.isPlaying, on: self)
      .store(in: &cancellables)

    player.$progress
      .assign(to: \.progress, on: self)
      .store(in: &cancellables)

    player.$current
      .assign(to: \.current, on: self)
      .store(in: &cancellables)

    player.$remaining
      .assign(to: \.remaining, on: self)
      .store(in: &cancellables)

    player.$total
      .assign(to: \.total, on: self)
      .store(in: &cancellables)

    player.$totalTimeRemaining
      .assign(to: \.totalTimeRemaining, on: self)
      .store(in: &cancellables)

    bookID = player.id
    title = player.title
    author = player.author ?? ""
    coverURL = player.coverURL
    playbackSpeed = 1.0
  }

  private func setupRemotePlayerBindings() {
    cancellables.removeAll()

    connectivityManager.$isPlaying
      .assign(to: \.isPlaying, on: self)
      .store(in: &cancellables)

    connectivityManager.$progress
      .assign(to: \.progress, on: self)
      .store(in: &cancellables)

    connectivityManager.$current
      .assign(to: \.current, on: self)
      .store(in: &cancellables)

    connectivityManager.$remaining
      .assign(to: \.remaining, on: self)
      .store(in: &cancellables)

    connectivityManager.$total
      .assign(to: \.total, on: self)
      .store(in: &cancellables)

    connectivityManager.$totalTimeRemaining
      .assign(to: \.totalTimeRemaining, on: self)
      .store(in: &cancellables)

    connectivityManager.$bookID
      .assign(to: \.bookID, on: self)
      .store(in: &cancellables)

    connectivityManager.$title
      .assign(to: \.title, on: self)
      .store(in: &cancellables)

    connectivityManager.$author
      .assign(to: \.author, on: self)
      .store(in: &cancellables)

    connectivityManager.$coverURL
      .assign(to: \.coverURL, on: self)
      .store(in: &cancellables)

    connectivityManager.$playbackSpeed
      .assign(to: \.playbackSpeed, on: self)
      .store(in: &cancellables)

    connectivityManager.$hasActivePlayer
      .assign(to: \.hasActivePlayer, on: self)
      .store(in: &cancellables)
  }

  override func togglePlayback() {
    if let player = playerManager.current {
      player.onTogglePlaybackTapped()
    } else {
      connectivityManager.togglePlayback()
    }
  }

  override func skipBackward() {
    if let player = playerManager.current {
      player.onSkipBackwardTapped()
    } else {
      connectivityManager.skipBackward()
    }
  }

  override func skipForward() {
    if let player = playerManager.current {
      player.onSkipForwardTapped()
    } else {
      connectivityManager.skipForward()
    }
  }
}
