import AVFoundation
import Foundation

final class AlarmPickerSheetViewModel: AlarmPickerSheet.Model {
  private let preferences = UserPreferences.shared
  private let itemID: String
  private let player: AudioPlayer
  private weak var timerViewModel: TimerPickerSheetViewModel?
  private let notificationService = AlarmNotificationService.shared

  private var countdownTimer: Timer?
  private var alarmSoundPlayer: AVAudioPlayer?
  private var fadeWindowSeconds: TimeInterval { preferences.alarmFadeOut }

  init(itemID: String, player: AudioPlayer, timerViewModel: TimerPickerSheetViewModel?) {
    self.itemID = itemID
    self.player = player
    self.timerViewModel = timerViewModel
    super.init()

    let totalMinutes = preferences.customAlarmDurationMinutes
    durationHours = totalMinutes / 60
    durationMinutes = totalMinutes % 60

    selectedTime =
      Calendar.current.date(
        bySettingHour: 7,
        minute: 0,
        second: 0,
        of: .now
      ) ?? .now
  }

  override func onStartTapped() {
    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil

    let triggerDate = makeTriggerDate()
    current = .init(nextTrigger: triggerDate)
    countdownText = formatCountdown(triggerDate.timeIntervalSinceNow)

    if mode == .duration {
      let totalMinutes = max(1, durationHours * 60 + durationMinutes)
      preferences.customAlarmDurationMinutes = totalMinutes
    }

    startMonitoring()
    scheduleNotifications(triggerDate: triggerDate)
    isPresented = false
  }

  override func onOffSelected() {
    stopMonitoring()
    current = nil
    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil
    player.volume = Float(preferences.volumeLevel)
    countdownText = "00:00:00"
    notificationService.cancel(itemID: itemID)
    isPresented = false
  }

  override func onAddTimeTapped() {
    addTime(minutes: addTimeMinutes)
  }

  override func onAddTimeMinutesChanged(_ value: Int) {
    addTimeMinutes = max(1, min(30, value))
  }

  private func startMonitoring() {
    stopMonitoring()
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
    if let countdownTimer {
      RunLoop.current.add(countdownTimer, forMode: .common)
    }
  }

  private func stopMonitoring() {
    countdownTimer?.invalidate()
    countdownTimer = nil
  }

  private func addTime(minutes: Int) {
    guard var current else { return }

    alarmSoundPlayer?.stop()
    alarmSoundPlayer = nil

    let baseTime = max(current.nextTrigger, Date())
    let nextTrigger = baseTime.addingTimeInterval(TimeInterval(minutes * 60))
    current.nextTrigger = nextTrigger
    self.current = current
    countdownText = formatCountdown(current.nextTrigger.timeIntervalSinceNow)
    player.volume = Float(preferences.volumeLevel)

    startMonitoring()
    scheduleNotifications(triggerDate: nextTrigger)
  }

  private func tick() {
    guard let activeAlarm = current else {
      stopMonitoring()
      return
    }

    let remaining = activeAlarm.nextTrigger.timeIntervalSinceNow

    if remaining <= 0 {
      countdownText = "00:00:00"
      player.pause()
      playAlarmTone()
      stopMonitoring()
      return
    }
    countdownText = formatCountdown(remaining)

    if player.isPlaying, fadeWindowSeconds > 0, remaining <= fadeWindowSeconds {
      timerViewModel?.applyFadeOut(
        secondsRemaining: max(1, ceil(remaining)),
        fadeDuration: fadeWindowSeconds
      )
    }
  }

  private func playAlarmTone() {
    guard let url = Bundle.main.url(forResource: "alarm_tone", withExtension: "wav") else {
      return
    }

    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.numberOfLoops = -1
      player.prepareToPlay()
      player.play()
      alarmSoundPlayer = player
    } catch {
      alarmSoundPlayer = nil
    }
  }

  private func formatCountdown(_ remaining: TimeInterval) -> String {
    let seconds = max(0, Int(remaining.rounded(.down)))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
  }

  private func makeTriggerDate() -> Date {
    switch mode {
    case .atTime:
      let calendar = Calendar.current
      let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
      let next = calendar.nextDate(
        after: .now,
        matching: DateComponents(hour: components.hour, minute: components.minute),
        matchingPolicy: .nextTime
      )
      return next ?? Date().addingTimeInterval(60)

    case .duration:
      let totalMinutes = max(1, durationHours * 60 + durationMinutes)
      return Date().addingTimeInterval(TimeInterval(totalMinutes * 60))
    }
  }

  private func scheduleNotifications(triggerDate: Date) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let hasPermission = await self.notificationService.requestAuthorizationIfNeeded()
      guard hasPermission else { return }
      await self.notificationService.schedule(
        itemID: self.itemID,
        triggerDate: triggerDate
      )
    }
  }
}
