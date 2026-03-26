import Combine
import Models
import WidgetKit

final class WidgetManager {
  private let id: String
  private let title: String
  private let author: String?
  private let coverURL: URL?
  private let watchConnectivity = WatchConnectivityManager.shared

  private weak var player: AudioPlayer?
  private var chapters: ChapterPickerSheet.Model?
  private var mediaProgress: MediaProgress?
  private var playbackProgress: PlaybackProgressView.Model?
  private var cancellables = Set<AnyCancellable>()
  private var lastSyncedTime: TimeInterval = 0

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
    player: AudioPlayer,
    chapters: ChapterPickerSheet.Model?,
    mediaProgress: MediaProgress,
    playbackProgress: PlaybackProgressView.Model
  ) {
    self.player = player
    self.chapters = chapters
    self.mediaProgress = mediaProgress
    self.playbackProgress = playbackProgress

    player.events
      .sink { [weak self] event in
        guard let self else { return }
        if case .rateChanged(let rate) = event {
          self.watchConnectivity.sendPlaybackRate(rate)
          self.update()
        }
      }
      .store(in: &cancellables)

    observeProgressChanges()
    observeChapterChanges()

    update()
    watchConnectivity.sendPlaybackRate(player.rate)
  }

  func clear() {
    cancellables.removeAll()
    watchConnectivity.sendPlaybackRate(nil)
  }

  func update() {
    guard let mediaProgress else { return }

    let isPlaying = player?.isPlaying ?? false

    let state = PlaybackState(
      bookID: id,
      title: title,
      author: author ?? "",
      coverURL: coverURL,
      currentTime: mediaProgress.currentTime,
      duration: mediaProgress.duration,
      isPlaying: isPlaying,
      playbackSpeed: player?.rate ?? 1.0
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

  private func observeProgressChanges() {
    guard let mediaProgress else { return }

    withObservationTracking {
      _ = mediaProgress.currentTime
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        let currentTime = self.mediaProgress?.currentTime ?? 0
        if abs(currentTime - self.lastSyncedTime) >= 10 {
          self.lastSyncedTime = currentTime
          self.update()
        }
        self.observeProgressChanges()
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
}
