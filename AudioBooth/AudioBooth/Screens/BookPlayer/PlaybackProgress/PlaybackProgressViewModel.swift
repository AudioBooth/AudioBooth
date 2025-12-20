import AVFoundation
import Models
import SwiftUI

final class PlaybackProgressViewModel: PlaybackProgressView.Model {
  private var itemID: String
  private var player: AVPlayer?
  private var chapters: ChapterPickerSheet.Model?
  private var speed: SpeedPickerSheet.Model?
  private let preferences = UserPreferences.shared
  private var onSeekCompleted: (() -> Void)?

  private let mediaProgress: MediaProgress

  init(itemID: String, mediaProgress: MediaProgress) {
    self.itemID = itemID
    self.mediaProgress = mediaProgress

    super.init(
      progress: 0,
      current: 0,
      remaining: 0,
      total: mediaProgress.duration,
      totalProgress: mediaProgress.progress,
      totalTimeRemaining: mediaProgress.remaining
    )

    observeMediaProgress()
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

    let currentTime = mediaProgress.currentTime
    var current: TimeInterval
    var remaining: TimeInterval
    let progress: CGFloat

    if let chapters, chapters.current != nil {
      current = chapters.currentElapsedTime(currentTime: currentTime)
      remaining = chapters.currentRemainingTime(currentTime: currentTime)
      progress = CGFloat(chapters.currentProgress(currentTime: currentTime))
    } else {
      current = currentTime
      remaining = total - currentTime
      progress = CGFloat(currentTime / total)
    }

    if let speed, preferences.chapterProgressionAdjustsWithSpeed, speed.playbackSpeed != 1.0 {
      let playbackSpeed = Double(speed.playbackSpeed)
      let adjustedTotal = (current + remaining) / playbackSpeed
      current = (current / playbackSpeed).rounded()
      remaining = adjustedTotal - current
    }

    var totalTimeRemaining = (total - currentTime)
    if let speed, preferences.timeRemainingAdjustsWithSpeed {
      totalTimeRemaining /= Double(speed.playbackSpeed)
    }

    self.progress = progress
    self.current = current
    self.remaining = remaining
    self.total = total
    self.totalProgress = currentTime / total
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
}
