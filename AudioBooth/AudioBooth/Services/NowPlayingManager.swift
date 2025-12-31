import API
import AVFoundation
import Combine
import Foundation
import Logging
import MediaPlayer
import Models
import Nuke

final class NowPlayingManager {
  private var info: [String: Any]
  private let id: String
  private let title: String
  private let author: String?
  private var artwork: MPMediaItemArtwork?
  private let preferences = UserPreferences.shared
  private var playbackState: MPNowPlayingPlaybackState = .paused

  private weak var player: AVPlayer?
  private var speed: SpeedPickerSheet.Model?
  private var chapters: ChapterPickerSheet.Model?
  private var mediaProgress: MediaProgress?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()

  init(
    id: String,
    title: String,
    author: String?,
    coverURL: URL?,
    current: TimeInterval,
    duration: TimeInterval
  ) {
    self.info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

    self.id = id
    self.title = title
    self.author = author

    primeNowPlaying()

    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = id
    info[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] = Audiobookshelf.shared.authentication.server?.id

    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = author

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current

    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    if let coverURL {
      loadArtwork(from: coverURL)
    }
  }

  private func primeNowPlaying() {
    Task {
      do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        try audioSession.setActive(true)

        let url = URL(string: "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=")!
        let player = AVPlayer(url: url)
        player.volume = 0
        player.play()
        try? await Task.sleep(for: .milliseconds(100))
        player.pause()
      } catch {
        AppLogger.player.debug("Failed to prime Now Playing: \(error)")
      }
    }
  }

  func configure(
    player: AVPlayer,
    speed: SpeedPickerSheet.Model,
    chapters: ChapterPickerSheet.Model?,
    mediaProgress: MediaProgress
  ) {
    self.player = player
    self.speed = speed
    self.chapters = chapters
    self.mediaProgress = mediaProgress

    observePlayerRate()
    observeSpeedChanges()
    observeChapterChanges()
    observePreferenceChanges()

    updateNowPlaying()
  }

  func didSeek(to time: TimeInterval) {
    updateNowPlaying()
  }

  func clear() {
    timeObserver = nil
    cancellables.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func observePlayerRate() {
    guard let player else { return }

    player.publisher(for: \.rate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateNowPlaying()
      }
      .store(in: &cancellables)
  }

  private func observeSpeedChanges() {
    guard let speed else { return }

    withObservationTracking {
      _ = speed.playbackSpeed
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.updateNowPlaying()
        self.observeSpeedChanges()
      }
    }
  }

  private func observeChapterChanges() {
    guard let chapters else { return }

    withObservationTracking {
      _ = chapters.current
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.updateNowPlaying()
        self.observeChapterChanges()
      }
    }
  }

  private func observePreferenceChanges() {
    withObservationTracking {
      _ = preferences.showFullBookDuration
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.updateNowPlaying()
        self.observePreferenceChanges()
      }
    }
  }

  private func updateNowPlaying() {
    guard let player, let mediaProgress else { return }

    info[MPMediaItemPropertyArtwork] = artwork

    let rate = player.rate
    playbackState = rate > 0 ? .playing : .paused
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = speed?.playbackSpeed ?? 1.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = rate

    if preferences.showFullBookDuration {
      info[MPMediaItemPropertyTitle] = title
      info[MPMediaItemPropertyArtist] = author
      info[MPMediaItemPropertyPlaybackDuration] = mediaProgress.duration
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = mediaProgress.currentTime
    } else if let chapters, let current = chapters.current {
      info[MPMediaItemPropertyTitle] = current.title
      info[MPMediaItemPropertyArtist] = title
      info[MPMediaItemPropertyPlaybackDuration] = current.end - current.start
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = chapters.currentElapsedTime(
        currentTime: mediaProgress.currentTime
      )
    } else {
      info[MPMediaItemPropertyTitle] = title
      info[MPMediaItemPropertyArtist] = author
      info[MPMediaItemPropertyPlaybackDuration] = mediaProgress.duration
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = mediaProgress.currentTime
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = playbackState
  }

  private func loadArtwork(from url: URL) {
    Task {
      do {
        let request = ImageRequest(url: url)
        let image = try await ImagePipeline.shared.image(for: request)

        artwork = MPMediaItemArtwork(
          boundsSize: image.size,
          requestHandler: { _ in image }
        )

        info[MPMediaItemPropertyArtwork] = artwork
        updateNowPlaying()
      } catch {
        AppLogger.player.error("Failed to load cover image for now playing: \(error)")
      }
    }
  }
}
