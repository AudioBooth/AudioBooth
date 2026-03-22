import AVFoundation
import Combine
import Models
import WidgetKit

final class WidgetManager {
  private let id: String
  private let title: String
  private let author: String?
  private let coverURL: URL?
  private let watchConnectivity = WatchConnectivityManager.shared

  private weak var player: AVPlayer?
  private var speed: FloatPickerSheet.Model?
  private var chapters: ChapterPickerSheet.Model?
  private var mediaProgress: MediaProgress?
  private var playbackProgress: PlaybackProgressView.Model?
  private var cancellables = Set<AnyCancellable>()
  private var timeObserver: Any?
  private var lastSyncedTime: Double = 0

  init(
    id: String,
    title: String,
    author: String?,
    coverURL: URL?
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.coverURL = coverURL
  }

  func configure(
    player: AVPlayer,
    speed: FloatPickerSheet.Model,
    chapters: ChapterPickerSheet.Model?,
    mediaProgress: MediaProgress,
    playbackProgress: PlaybackProgressView.Model
  ) {
    self.player = player
    self.speed = speed
    self.chapters = chapters
    self.mediaProgress = mediaProgress
    self.playbackProgress = playbackProgress

    observePlayerRate()
    observeSpeedChanges()
    observeChapterChanges()
    observeSeekEvents()
    observePeriodicProgress()

    update()
    watchConnectivity.sendPlaybackRate(Float(speed.value))
  }

  func clear() {
    if let timeObserver, let player {
      player.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    cancellables.removeAll()
    watchConnectivity.sendPlaybackRate(nil)
  }

  func update() {
    guard let mediaProgress else { return }

    let isPlaying = (player?.rate ?? 0) > 0

    let state = PlaybackState(
      bookID: id,
      title: title,
      author: author ?? "",
      coverURL: coverURL,
      currentTime: mediaProgress.currentTime,
      duration: mediaProgress.duration,
      isPlaying: isPlaying,
      playbackSpeed: Float(speed?.value ?? 1.0)
    )

    if let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS"),
      let data = try? JSONEncoder().encode(state)
    {
      sharedDefaults.set(data, forKey: "playbackState")
      WidgetCenter.shared.reloadAllTimelines()
    }

    let chapterProgress: Double? =
      if let playbackProgress,
        playbackProgress.progress != playbackProgress.totalProgress
      {
        playbackProgress.progress
      } else {
        nil
      }

    watchConnectivity.syncProgress(id, chapterProgress: chapterProgress)
  }

  private func observePlayerRate() {
    guard let player else { return }

    player.publisher(for: \.rate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.update()
      }
      .store(in: &cancellables)
  }

  private func observeSpeedChanges() {
    guard let speed else { return }

    withObservationTracking {
      _ = speed.value
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        if let speed = self.speed {
          self.watchConnectivity.sendPlaybackRate(Float(speed.value))
        }
        self.update()
        self.observeSpeedChanges()
      }
    }
  }

  private func observeChapterChanges() {
    guard let chapters else { return }

    withObservationTracking {
      _ = chapters.currentIndex
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.update()
        self.observeChapterChanges()
      }
    }
  }

  private func observeSeekEvents() {
    NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.update()
      }
      .store(in: &cancellables)
  }

  private func observePeriodicProgress() {
    guard let player else { return }

    let interval = CMTime(seconds: 5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      guard let self else { return }
      let currentTime = CMTimeGetSeconds(time)
      if abs(currentTime - lastSyncedTime) >= 10 {
        lastSyncedTime = currentTime
        update()
      }
    }
  }
}
