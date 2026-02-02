import AVFoundation
import ActivityKit
import Combine
import Foundation
import Logging
import PlayerIntents
import SwiftUI

final class TimerPickerSheetViewModel: TimerPickerSheet.Model {
  private let preferences = UserPreferences.shared
  private let player: AVPlayer
  private let chapters: ChapterPickerSheet.Model?
  private let speed: SpeedPickerSheet.Model

  private var sleepTimer: Timer?
  private var timerStartTime: Date?
  private var originalTimerDuration: TimeInterval = 0
  private var lastObservedChapterIndex: Int = 0
  private var cancellables = Set<AnyCancellable>()
  private var playbackObserver: AnyCancellable?
  private var seekObserver: AnyCancellable?
  private var liveActivity: Activity<SleepTimerActivityAttributes>?

  init(player: AVPlayer, chapters: ChapterPickerSheet.Model?, speed: SpeedPickerSheet.Model) {
    self.player = player
    self.chapters = chapters
    self.speed = speed

    super.init()

    let totalMinutes = preferences.customTimerMinutes
    customHours = totalMinutes / 60
    customMinutes = totalMinutes % 60

    if let chapters {
      maxRemainingChapters = chapters.chapters.count - chapters.currentIndex - 1
      lastObservedChapterIndex = chapters.currentIndex
    }

    ShakeDetector.shared.stopMonitoring()
    setupShakeObserver()
    observeChapterChanges()
  }

  private func setupShakeObserver() {
    ShakeDetector.shared.shakePublisher
      .sink { [weak self] in
        self?.onShakeDetected()
      }
      .store(in: &cancellables)
  }

  private func observeChapterChanges() {
    guard let chapters else { return }

    withObservationTracking {
      _ = chapters.currentIndex
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.handleChapterChange()
        self.observeChapterChanges()
      }
    }
  }

  private func handleChapterChange() {
    guard let chapters else { return }

    let currentIndex = chapters.currentIndex
    let total = chapters.chapters.count
    maxRemainingChapters = total - currentIndex - 1

    if case .chapters(let chaptersRemaining) = self.current {
      if lastObservedChapterIndex < currentIndex {
        if chaptersRemaining > 1 {
          self.current = .chapters(chaptersRemaining - 1)
        } else {
          pauseFromChapterTimer()
        }
      }
    }

    lastObservedChapterIndex = currentIndex
  }

  override var isPresented: Bool {
    didSet {
      if isPresented && !oldValue {
        selected = current
        if case .chapters(let count) = current {
          updateEstimatedEndTime(for: count)
        }
      }
    }
  }

  override func onQuickTimerSelected(_ minutes: Int) {
    let duration = TimeInterval(minutes * 60)
    selected = .preset(duration)
    estimatedEndTime = nil
    onStartTimerTapped()
  }

  override func onChaptersChanged(_ value: Int) {
    selected = .chapters(value)
    updateEstimatedEndTime(for: value)
  }

  private func updateEstimatedEndTime(for chapterCount: Int) {
    guard let chapters, chapterCount > 0 else {
      estimatedEndTime = nil
      return
    }

    let currentTime = CMTimeGetSeconds(player.currentTime())
    let currentIndex = chapters.currentIndex
    let allChapters = chapters.chapters

    guard currentIndex < allChapters.count else {
      estimatedEndTime = nil
      return
    }

    var totalSeconds: TimeInterval = 0

    let currentChapter = allChapters[currentIndex]
    totalSeconds += max(0, currentChapter.end - currentTime)

    let additionalChaptersNeeded = chapterCount - 1
    if additionalChaptersNeeded > 0 {
      for i in 1...additionalChaptersNeeded {
        let chapterIndex = currentIndex + i
        guard chapterIndex < allChapters.count else { break }
        let chapter = allChapters[chapterIndex]
        totalSeconds += chapter.end - chapter.start
      }
    }

    let playbackSpeed = Double(speed.playbackSpeed)
    let adjustedSeconds = totalSeconds / playbackSpeed

    let endDate = Date().addingTimeInterval(adjustedSeconds)
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    estimatedEndTime = "Pauses at \(formatter.string(from: endDate))"
  }

  override func onOffSelected() {
    selected = .none
    current = .none
    completedAlert = nil
    estimatedEndTime = nil
    stopSleepTimer()
    stopObservingPlaybackState()
    endLiveActivity()
    isPresented = false
  }

  override func onStartTimerTapped() {
    current = selected
    switch selected {
    case .preset(let duration):
      startSleepTimer(duration: duration)
    case .custom(let duration):
      let totalMinutes = customHours * 60 + customMinutes
      preferences.customTimerMinutes = totalMinutes
      startSleepTimer(duration: duration)
    case .chapters(let count):
      if let duration = calculateChapterDuration(for: count) {
        startLiveActivity(duration: duration)
      }
      startObservingPlaybackState()
    case .none:
      break
    }
    isPresented = false

    player.play()
  }

  private func calculateChapterDuration(for chapterCount: Int) -> TimeInterval? {
    guard let chapters, chapterCount > 0 else { return nil }

    let currentTime = CMTimeGetSeconds(player.currentTime())
    let currentIndex = chapters.currentIndex
    let allChapters = chapters.chapters

    guard currentIndex < allChapters.count else { return nil }

    var totalSeconds: TimeInterval = 0

    let currentChapter = allChapters[currentIndex]
    totalSeconds += max(0, currentChapter.end - currentTime)

    let additionalChaptersNeeded = chapterCount - 1
    if additionalChaptersNeeded > 0 {
      for i in 1...additionalChaptersNeeded {
        let chapterIndex = currentIndex + i
        guard chapterIndex < allChapters.count else { break }
        let chapter = allChapters[chapterIndex]
        totalSeconds += chapter.end - chapter.start
      }
    }

    let playbackSpeed = Double(speed.playbackSpeed)
    return totalSeconds / playbackSpeed
  }

  private func startSleepTimer(duration: TimeInterval) {
    stopSleepTimer()
    timerStartTime = Date()
    originalTimerDuration = duration

    sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.updateSleepTimer()
    }

    RunLoop.current.add(sleepTimer!, forMode: .common)

    ShakeDetector.shared.startMonitoring()

    startLiveActivity(duration: duration)
  }

  private func stopSleepTimer() {
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil
    originalTimerDuration = 0

    ShakeDetector.shared.stopMonitoring()
    endLiveActivity()
  }

  private func updateSleepTimer() {
    switch current {
    case .preset(let seconds):
      if seconds > 1 {
        fadeOut(seconds)
        current = .preset(seconds - 1)
      } else {
        pauseFromTimer()
      }

    case .custom(let seconds):
      if seconds > 1 {
        fadeOut(seconds)
        current = .custom(seconds - 1)
      } else {
        pauseFromTimer()
      }

    case .none, .chapters:
      stopSleepTimer()
    }
  }

  private func fadeOut(_ seconds: TimeInterval) {
    let fadeOut = preferences.timerFadeOut
    if fadeOut > 0, seconds < fadeOut {
      player.volume = Float(seconds / fadeOut) * Float(preferences.volumeLevel)
    }
  }

  private func pauseFromTimer() {
    let duration = originalTimerDuration

    player.pause()
    player.volume = Float(preferences.volumeLevel)

    if preferences.shakeSensitivity.isEnabled {
      let extendAction = formatExtendButtonTitle(for: duration)
      completedAlert = TimerCompletedAlertViewModel(
        extendAction: extendAction,
        onExtend: { [weak self] in
          self?.extendTimer()
        },
        onReset: { [weak self] in
          self?.resetTimerFromAlert()
        }
      )
    }

    current = .none
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil

    pauseLiveActivity(remaining: originalTimerDuration)

    AppLogger.player.info("Timer expired - playback paused")
  }

  private func formatExtendButtonTitle(for duration: TimeInterval) -> String {
    let formattedDuration = Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )
    return String(localized: "Extend \(formattedDuration)")
  }

  private func extendTimer() {
    guard originalTimerDuration > 0 else {
      completedAlert = nil
      return
    }

    startSleepTimer(duration: originalTimerDuration)
    current = .preset(originalTimerDuration)

    player.play()

    completedAlert = nil
    AppLogger.player.info("Timer extended by \(self.originalTimerDuration) seconds")
  }

  private func resetTimerFromAlert() {
    completedAlert = nil
    current = .none
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil
    originalTimerDuration = 0

    ShakeDetector.shared.stopMonitoring()
    endLiveActivity()
    stopObservingPlaybackState()

    AppLogger.player.info("Timer reset from alert")
  }

  func pauseFromChapterTimer() {
    player.pause()
    stopObservingPlaybackState()

    if preferences.shakeSensitivity.isEnabled {
      completedAlert = TimerCompletedAlertViewModel(
        extendAction: "Extend to end of chapter",
        onExtend: { [weak self] in
          self?.extendChapterTimer()
        },
        onReset: { [weak self] in
          self?.resetTimerFromAlert()
        }
      )
    }

    current = .none
    AppLogger.player.info("Chapter timer expired - playback paused")
  }

  private func extendChapterTimer() {
    current = .chapters(1)

    if let duration = calculateChapterDuration(for: 1) {
      startLiveActivity(duration: duration)
    }
    startObservingPlaybackState()

    player.play()

    completedAlert = nil
    AppLogger.player.info("Chapter timer extended by 1 chapter")
  }

  private func currentTimeInMinutes() -> Int {
    let now = Date()
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: now)
    let minute = calendar.component(.minute, from: now)
    return hour * 60 + minute
  }

  private func isInAutoTimerWindow() -> Bool {
    let currentMinutes = currentTimeInMinutes()
    let startMinutes = preferences.autoTimerWindowStart
    let endMinutes = preferences.autoTimerWindowEnd

    if startMinutes < endMinutes {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes
    }
  }

  func activateAutoTimerIfNeeded() {
    let mode = preferences.autoTimerMode

    guard mode != .off,
      current == .none,
      isInAutoTimerWindow()
    else {
      return
    }

    switch mode {
    case .duration(let duration):
      current = .preset(duration)
      startSleepTimer(duration: duration)
      AppLogger.player.info("Auto-timer activated: \(duration) seconds")

    case .chapters(let count):
      current = .chapters(count)
      if let duration = calculateChapterDuration(for: count) {
        startLiveActivity(duration: duration)
      }
      startObservingPlaybackState()
      AppLogger.player.info("Auto-timer activated: \(count) chapters")

    case .off:
      break
    }
  }

  func onShakeDetected() {
    guard preferences.shakeSensitivity.isEnabled, originalTimerDuration > 0 else { return }

    player.volume = Float(preferences.volumeLevel)

    switch current {
    case .preset:
      current = .preset(originalTimerDuration)
      startSleepTimer(duration: originalTimerDuration)
      AppLogger.player.info("Preset timer reset to \(originalTimerDuration) seconds via shake")

    case .custom:
      current = .custom(originalTimerDuration)
      startSleepTimer(duration: originalTimerDuration)
      AppLogger.player.info("Custom timer reset to \(originalTimerDuration) seconds via shake")

    case .chapters:
      AppLogger.player.debug("Shake detected during chapter timer - no reset action")

    case .none:
      break
    }
  }
}

// MARK: - Live Activity

extension TimerPickerSheetViewModel {
  func startLiveActivity(duration: TimeInterval) {
    let endTime = Date().addingTimeInterval(duration)
    let state = SleepTimerActivityAttributes.ContentState(
      timer: .countdown(endTime),
      accentColor: preferences.accentColor
    )

    if liveActivity != nil {
      updateLiveActivity(state)
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      AppLogger.player.debug("Live Activities not enabled")
      return
    }

    let attributes = SleepTimerActivityAttributes()
    do {
      liveActivity = try Activity.request(
        attributes: attributes,
        content: .init(state: state, staleDate: endTime),
        pushType: nil
      )
      AppLogger.player.info("Sleep timer Live Activity started")
    } catch {
      AppLogger.player.error("Failed to start Live Activity: \(error)")
    }
  }

  func updateLiveActivity(_ state: SleepTimerActivityAttributes.ContentState) {
    guard let liveActivity else { return }

    let staleDate: Date? = if case .countdown(let endTime) = state.timer { endTime } else { nil }
    Task {
      await liveActivity.update(.init(state: state, staleDate: staleDate))
    }
  }

  func endLiveActivity() {
    guard let liveActivity else { return }

    Task {
      await liveActivity.end(nil, dismissalPolicy: .immediate)
      AppLogger.player.info("Sleep timer Live Activity ended")
    }
    self.liveActivity = nil
  }

  func startObservingPlaybackState() {
    playbackObserver = player.publisher(for: \.timeControlStatus)
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self, case .chapters(let count) = self.current else { return }
        switch status {
        case .playing:
          if let duration = self.calculateChapterDuration(for: count) {
            self.startLiveActivity(duration: duration)
          }
        case .paused:
          self.pauseLiveActivity()
        case .waitingToPlayAtSpecifiedRate:
          break
        @unknown default:
          break
        }
      }

    seekObserver = NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
      .sink { [weak self] _ in
        guard let self,
          case .chapters(let count) = self.current,
          self.player.timeControlStatus == .playing,
          let duration = self.calculateChapterDuration(for: count)
        else { return }
        self.startLiveActivity(duration: duration)
      }
  }

  func pauseLiveActivity(remaining: TimeInterval? = nil) {
    guard liveActivity != nil else { return }

    let remainingTime: TimeInterval
    if let remaining {
      remainingTime = remaining
    } else if case .chapters(let count) = current {
      remainingTime = calculateChapterDuration(for: count) ?? 0
    } else {
      remainingTime = 0
    }

    let state = SleepTimerActivityAttributes.ContentState(
      timer: .paused(remainingTime),
      accentColor: preferences.accentColor
    )
    updateLiveActivity(state)
  }

  func stopObservingPlaybackState() {
    playbackObserver?.cancel()
    playbackObserver = nil
    seekObserver?.cancel()
    seekObserver = nil
  }
}
