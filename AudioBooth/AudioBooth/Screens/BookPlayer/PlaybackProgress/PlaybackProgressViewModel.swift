import AVFoundation
import Combine
import Models
import SwiftUI

final class PlaybackProgressViewModel: PlaybackProgressView.Model {
  private var itemID: String
  private var player: AVPlayer?
  private var chapters: ChapterPickerSheet.Model?
  private var speed: SpeedPickerSheet.Model?
  private let preferences = UserPreferences.shared
  private var onSeekCompleted: (() -> Void)?
  private var cancellables = Set<AnyCancellable>()

  private let mediaProgress: MediaProgress

  init(itemID: String, mediaProgress: MediaProgress, title: String) {
    self.itemID = itemID
    self.mediaProgress = mediaProgress

    super.init(
      progress: 0,
      current: 0,
      remaining: 0,
      total: mediaProgress.duration,
      totalProgress: mediaProgress.progress,
      totalTimeRemaining: mediaProgress.remaining,
      title: title
    )

    observeMediaProgress()
    observePreferenceChanges()
  }

  private func observeMediaProgress() {
    withObservationTracking {
      _ = mediaProgress.currentTime
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.updateProgress()
        self.observeMediaProgress()
      }
    }
  }

  func configure(
    player: AVPlayer?,
    chapters: ChapterPickerSheet.Model?,
    speed: SpeedPickerSheet.Model,
    onSeekCompleted: (() -> Void)? = nil
  ) {
    self.player = player
    self.chapters = chapters
    self.speed = speed
    self.onSeekCompleted = onSeekCompleted
    updateProgress()
  }

  func updateProgress() {
    guard !isDragging else { return }

    if preferences.showFullBookDuration {
      updateBookProgress()
    } else {
      updateChapterProgress()
    }
  }

  private func updateBookProgress() {
    let currentTime = mediaProgress.currentTime
    let totalDuration = total
    let overallProgress = currentTime / totalDuration

    var current: TimeInterval = currentTime
    var remaining: TimeInterval = totalDuration - currentTime
    let progress: CGFloat = CGFloat(overallProgress)

    if let speed, preferences.chapterProgressionAdjustsWithSpeed, speed.playbackSpeed != 1.0 {
      let playbackSpeed = Double(speed.playbackSpeed)
      let adjustedTotal = (current + remaining) / playbackSpeed
      current = (current / playbackSpeed).rounded()
      remaining = adjustedTotal - current
    }

    var totalTimeRemaining = (totalDuration - currentTime)
    if let speed, preferences.timeRemainingAdjustsWithSpeed {
      totalTimeRemaining /= Double(speed.playbackSpeed)
    }

    self.progress = progress
    self.current = current
    self.remaining = remaining
    self.totalProgress = overallProgress
    self.totalTimeRemaining = totalTimeRemaining
  }

  private func updateChapterProgress() {
    let currentTime = mediaProgress.currentTime
    let totalDuration = total
    let overallProgress = currentTime / totalDuration

    var current: TimeInterval
    var remaining: TimeInterval
    let progress: CGFloat

    if let chapters, chapters.current != nil {
      current = chapters.currentElapsedTime(currentTime: currentTime)
      remaining = chapters.currentRemainingTime(currentTime: currentTime)
      progress = CGFloat(chapters.currentProgress(currentTime: currentTime))
    } else {
      current = currentTime
      remaining = totalDuration - currentTime
      progress = CGFloat(overallProgress)
    }

    if let speed, preferences.chapterProgressionAdjustsWithSpeed, speed.playbackSpeed != 1.0 {
      let playbackSpeed = Double(speed.playbackSpeed)
      let adjustedTotal = (current + remaining) / playbackSpeed
      current = (current / playbackSpeed).rounded()
      remaining = adjustedTotal - current
    }

    var totalTimeRemaining = (totalDuration - currentTime)
    if let speed, preferences.timeRemainingAdjustsWithSpeed {
      totalTimeRemaining /= Double(speed.playbackSpeed)
    }

    self.progress = progress
    self.current = current
    self.remaining = remaining
    self.totalProgress = overallProgress
    self.totalTimeRemaining = totalTimeRemaining
  }

  override func onProgressChanged(_ progress: Double) {
    guard let player else { return }

    if let chapter = chapters?.current {
      let duration = chapter.end - chapter.start
      let currentTime = chapter.start + (duration * progress)
      player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000)) { [weak self] _ in
        self?.onSeekCompleted?()
      }
      PlaybackHistory.record(itemID: itemID, action: .seek, position: currentTime)
    } else {
      let currentTime = total * progress
      player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000)) { [weak self] _ in
        self?.onSeekCompleted?()
      }
      PlaybackHistory.record(itemID: itemID, action: .seek, position: currentTime)
    }
  }

  private func observePreferenceChanges() {
    preferences.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateProgress()
      }
      .store(in: &cancellables)
  }
}
