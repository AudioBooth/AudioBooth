import AVFoundation
import Models
import SwiftUI

final class PlaybackProgressViewModel: PlaybackProgressView.Model {
  private var itemID: String
  private var player: AVPlayer?
  private var chapters: ChapterPickerSheet.Model?
  private var speed: SpeedPickerSheet.Model?
  private var totalDuration: TimeInterval?
  private var currentTime: TimeInterval = 0
  private var isPlayerLoading: Bool = false
  private let preferences = UserPreferences.shared

  init(itemID: String) {
    self.itemID = itemID
    super.init(
      progress: 0,
      current: 0,
      remaining: 0,
      total: 0,
      totalProgress: 0,
      totalTimeRemaining: 0,
      isLoading: false
    )
  }

  func configure(
    player: AVPlayer?,
    chapters: ChapterPickerSheet.Model?,
    speed: SpeedPickerSheet.Model,
    totalDuration: TimeInterval?
  ) {
    self.player = player
    self.chapters = chapters
    self.speed = speed
    self.totalDuration = totalDuration
    updateProgress()
  }

  func updateCurrentTime(_ time: TimeInterval) {
    self.currentTime = time
    updateProgress()
  }

  func updateLoadingState(_ isLoading: Bool) {
    self.isPlayerLoading = isLoading
    self.isLoading = isLoading
  }

  func updateProgress() {
    guard let totalDuration else {
      progress = 0
      current = 0
      remaining = 0
      total = 0
      totalProgress = 0
      totalTimeRemaining = 0
      return
    }

    let currentTime = self.currentTime
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
      progress = CGFloat(currentTime / totalDuration)
    }

    if let speed, preferences.chapterProgressionAdjustsWithSpeed {
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
    self.total = totalDuration
    self.totalProgress = currentTime / totalDuration
    self.totalTimeRemaining = totalTimeRemaining
    self.isLoading = isPlayerLoading
  }

  override func onProgressChanged(_ progress: Double) {
    guard let player = player else { return }

    if let chapter = chapters?.current {
      let duration = chapter.end - chapter.start
      let seekTime = chapter.start + (duration * progress)
      player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      PlaybackHistory.record(itemID: itemID, action: .seek, position: seekTime)
    } else if let totalDuration {
      let seekTime = totalDuration * progress
      player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      PlaybackHistory.record(itemID: itemID, action: .seek, position: seekTime)
    }
  }
}
