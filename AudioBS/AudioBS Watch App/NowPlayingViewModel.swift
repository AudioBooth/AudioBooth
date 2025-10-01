import Combine
import Foundation

final class NowPlayingViewModel: NowPlayingView.Model {
  private var cancellables = Set<AnyCancellable>()
  private let connectivityManager = WatchConnectivityManager.shared

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
    connectivityManager.togglePlayback()
  }

  override func skipBackward() {
    connectivityManager.skipBackward()
  }

  override func skipForward() {
    connectivityManager.skipForward()
  }
}
