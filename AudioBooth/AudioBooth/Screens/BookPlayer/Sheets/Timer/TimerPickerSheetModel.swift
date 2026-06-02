import Combine
import AVFoundation
import Foundation
import Logging
import Models
import PlayerIntents
import SwiftUI

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

final class TimerPickerSheetViewModel: TimerPickerSheet.Model {
  private let preferences = UserPreferences.shared
  private let itemID: String
  let player: AudioPlayer
  private let chapters: ChapterPickerSheet.Model?
  private let speed: FloatPickerSheet.Model
  private let alarmNotificationService = AlarmNotificationService()

  private var sleepTimer: Timer?
  private var alarmTimer: Timer?
  private var alarmSoundPlayer: AVAudioPlayer?
  private var timerStartTime: Date?
  private var originalTimerDuration: TimeInterval = 0
  private var lastObservedChapterIndex: Int = 0
  private var cancellables = Set<AnyCancellable>()
  private var playbackObserver: AnyCancellable?
  private var seekObserver: AnyCancellable?
  private var liveActivityCleanupTask: Task<Void, Never>?
  #if !targetEnvironment(macCatalyst)
  private var liveActivity: Activity<SleepTimerActivityAttributes>?
  #endif

  init(itemID: String, player: AudioPlayer, chapters: ChapterPickerSheet.Model?, speed: FloatPickerSheet.Model) {
    self.itemID = itemID
    self.player = player
    self.chapters = chapters
    self.speed = speed

    super.init()

    let totalMinutes = preferences.customTimerMinutes
    customHours = totalMinutes / 60
    customMinutes = totalMinutes % 60

    let calendar = Calendar.current
    alarmSelectedTime =
      calendar.date(
        bySettingHour: 7,
        minute: 0,
        second: 0,
        of: .now
      ) ?? .now

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

    let currentTime = player.time
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

    let playbackSpeed = speed.value
    let adjustedSeconds = totalSeconds / playbackSpeed

    let endDate = Date().addingTimeInterval(adjustedSeconds)

    let time = endDate.formatted(date: .omitted, time: .shortened)

    estimatedEndTime = String(localized: "Pauses at \(time)")
  }

  override func onOffSelected() {
    selected = .none
    current = .none
    completedAlert = nil
    estimatedEndTime = nil
    stopSleepTimer()
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
    case .none:
      break
    }
    PlaybackHistory.record(itemID: itemID, action: .timerStarted, position: player.time)
    isPresented = false

    if !player.isPlaying {
      player.resume()
    }
  }

  private func calculateChapterDuration(for chapterCount: Int) -> TimeInterval? {
    guard let chapters, chapterCount > 0 else { return nil }

    let currentTime = player.time
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

    let playbackSpeed = speed.value
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

    PlaybackHistory.record(itemID: itemID, action: .timerCompleted, position: player.time)
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
    scheduleLiveActivityCleanup()

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
    PlaybackHistory.record(itemID: itemID, action: .timerExtended, position: player.time)

    player.resume()

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

    AppLogger.player.info("Timer reset from alert")
  }

  func pauseFromChapterTimer() {
    PlaybackHistory.record(itemID: itemID, action: .timerCompleted, position: player.time)
    player.pause()

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
    scheduleLiveActivityCleanup()
    AppLogger.player.info("Chapter timer expired - playback paused")
  }

  private func extendChapterTimer() {
    current = .chapters(1)

    if let duration = calculateChapterDuration(for: 1) {
      startLiveActivity(duration: duration)
    }
    PlaybackHistory.record(itemID: itemID, action: .timerExtended, position: player.time)

    player.resume()

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

    let position = player.time

    switch mode {
    case .duration(let duration):
      current = .preset(duration)
      startSleepTimer(duration: duration)
      PlaybackHistory.record(itemID: itemID, action: .timerStarted, position: position)
      AppLogger.player.info("Auto-timer activated: \(duration) seconds")

    case .chapters(let count):
      current = .chapters(count)
      if let duration = calculateChapterDuration(for: count) {
        startLiveActivity(duration: duration)
      }
      PlaybackHistory.record(itemID: itemID, action: .timerStarted, position: position)
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

  override func onAlarmStartTapped() {
    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil
    isAlarmRinging = false

    let triggerDate = makeAlarmTriggerDate()
    alarmCurrent = .init(nextTrigger: triggerDate)
    alarmCountdownText = formatAlarmCountdown(triggerDate.timeIntervalSinceNow)

    startAlarmTimer()
    scheduleAlarmNotification(triggerDate: triggerDate)
    isPresented = false
  }

  override func onAlarmOffTapped() {
    stopAlarmTimer()
    alarmCurrent = nil
    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil
    player.volume = Float(preferences.volumeLevel)
    alarmCountdownText = "00:00:00"
    isAlarmRinging = false
    alarmNotificationService.cancel()
    isPresented = false
  }

  override func onAlarmAddTimeTapped() {
    addAlarmTime(minutes: alarmAddTimeMinutes)
  }

  override func onAlarmAddTimeMinutesChanged(_ value: Int) {
    alarmAddTimeMinutes = max(1, min(30, value))
  }

  private func startAlarmTimer() {
    stopAlarmTimer()
    alarmTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.updateAlarm()
    }
    if let alarmTimer {
      RunLoop.current.add(alarmTimer, forMode: .common)
    }
  }

  private func stopAlarmTimer() {
    alarmTimer?.invalidate()
    alarmTimer = nil
  }

  private func updateAlarm() {
    guard let alarm = alarmCurrent else {
      stopAlarmTimer()
      return
    }

    let remaining = alarm.nextTrigger.timeIntervalSinceNow

    if remaining <= 0 {
      alarmCountdownText = "00:00:00"
      isAlarmRinging = true
      player.pause()
      playAlarmTone()
      stopAlarmTimer()
      return
    }

    alarmCountdownText = formatAlarmCountdown(remaining)
    isAlarmRinging = false

    let fadeDuration = preferences.alarmFadeOut
    if player.isPlaying, fadeDuration > 0, remaining <= fadeDuration {
      player.volume = Float(max(remaining, 1) / fadeDuration) * Float(preferences.volumeLevel)
    }
  }

  private func addAlarmTime(minutes: Int) {
    guard var alarm = alarmCurrent else { return }

    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil

    let baseTime = max(alarm.nextTrigger, Date())
    alarm.nextTrigger = baseTime.addingTimeInterval(TimeInterval(minutes * 60))
    alarmCurrent = alarm
    alarmCountdownText = formatAlarmCountdown(alarm.nextTrigger.timeIntervalSinceNow)
    player.volume = Float(preferences.volumeLevel)
    isAlarmRinging = false

    startAlarmTimer()
    scheduleAlarmNotification(triggerDate: alarm.nextTrigger)
  }

  private func playAlarmTone() {
    guard let url = Bundle.main.url(forResource: "alarm_tone", withExtension: "wav") else {
      return
    }

    do {
      let alarmPlayer = try AVAudioPlayer(contentsOf: url)
      alarmPlayer.numberOfLoops = -1
      alarmPlayer.prepareToPlay()
      alarmPlayer.play()
      alarmSoundPlayer = alarmPlayer
    } catch {
      alarmSoundPlayer = nil
    }
  }

  private func makeAlarmTriggerDate() -> Date {
    switch alarmMode {
    case .atTime:
      let calendar = Calendar.current
      let components = calendar.dateComponents([.hour, .minute], from: alarmSelectedTime)
      let next = calendar.nextDate(
        after: .now,
        matching: DateComponents(hour: components.hour, minute: components.minute),
        matchingPolicy: .nextTime
      )
      return next ?? Date().addingTimeInterval(60)

    case .duration:
      let totalMinutes = max(1, alarmDurationHours * 60 + alarmDurationMinutes)
      return Date().addingTimeInterval(TimeInterval(totalMinutes * 60))
    }
  }

  private func scheduleAlarmNotification(triggerDate: Date) {
    Task { [weak self] in
      guard let self else { return }
      let hasPermission = await alarmNotificationService.requestAuthorizationIfNeeded()
      guard hasPermission else { return }
      await alarmNotificationService.schedule(triggerDate: triggerDate)
    }
  }

  private func formatAlarmCountdown(_ remaining: TimeInterval) -> String {
    let seconds = max(0, Int(remaining.rounded(.down)))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
  }
}

extension TimerPickerSheetViewModel {
  #if !targetEnvironment(macCatalyst)
  func startLiveActivity(duration: TimeInterval) {
    liveActivityCleanupTask?.cancel()
    liveActivityCleanupTask = nil

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
    liveActivityCleanupTask?.cancel()
    liveActivityCleanupTask = nil

    guard let liveActivity else { return }

    Task {
      await liveActivity.end(nil, dismissalPolicy: .immediate)
      AppLogger.player.info("Sleep timer Live Activity ended")
    }
    self.liveActivity = nil
  }

  func scheduleLiveActivityCleanup() {
    liveActivityCleanupTask?.cancel()
    liveActivityCleanupTask = Task {
      do {
        try await Task.sleep(for: .seconds(300))
        guard !Task.isCancelled else { return }
        endLiveActivity()
        AppLogger.player.info("Live Activity cleaned up after 5 minutes of inactivity")
      } catch {}
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
  func resumeLiveActivityIfNeeded() {
    guard liveActivity != nil else { return }

    let duration: TimeInterval
    switch current {
    case .preset(let remaining), .custom(let remaining):
      duration = remaining
    case .chapters(let count):
      duration = calculateChapterDuration(for: count) ?? 0
    case .none:
      return
    }

    let endTime = Date().addingTimeInterval(duration)
    let state = SleepTimerActivityAttributes.ContentState(
      timer: .countdown(endTime),
      accentColor: preferences.accentColor
    )
    updateLiveActivity(state)
  }
  #else
  func startLiveActivity(duration: TimeInterval) {}
  func updateLiveActivity(_ state: Any) {}
  func endLiveActivity() {}
  func pauseLiveActivity(remaining: TimeInterval? = nil) {}
  func scheduleLiveActivityCleanup() {}
  func resumeLiveActivityIfNeeded() {}
  #endif
}
