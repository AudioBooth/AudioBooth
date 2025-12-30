import AVFoundation
import Combine
import Foundation
import Logging
import SwiftUI

final class TimerPickerSheetViewModel: TimerPickerSheet.Model {
  private let preferences = UserPreferences.shared

  private weak var player: AVPlayer?
  private var sleepTimer: Timer?
  private var timerStartTime: Date?
  private var originalTimerDuration: TimeInterval = 0
  private var currentChapterIndex: Int = 0
  private var cancellables = Set<AnyCancellable>()

  override init() {
    super.init()

    let totalMinutes = preferences.customTimerMinutes
    customHours = totalMinutes / 60
    customMinutes = totalMinutes % 60

    ShakeDetector.shared.stopMonitoring()
    setupShakeObserver()
  }

  private func setupShakeObserver() {
    ShakeDetector.shared.shakePublisher
      .sink { [weak self] in
        self?.onShakeDetected()
      }
      .store(in: &cancellables)
  }

  func setPlayer(_ player: AVPlayer?) {
    self.player = player
  }

  override var isPresented: Bool {
    didSet {
      if isPresented && !oldValue {
        selected = current
      }
    }
  }

  override func onQuickTimerSelected(_ minutes: Int) {
    let duration = TimeInterval(minutes * 60)
    selected = .preset(duration)
    onStartTimerTapped()
  }

  override func onChaptersChanged(_ value: Int) {
    selected = .chapters(value)
    if value == 1 {
      onStartTimerTapped()
    }
  }

  override func onOffSelected() {
    selected = .none
    current = .none
    completedAlert = nil
    stopSleepTimer()
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
    case .chapters:
      break
    case .none:
      break
    }
    isPresented = false

    player?.play()
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
  }

  private func stopSleepTimer() {
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil
    originalTimerDuration = 0

    ShakeDetector.shared.stopMonitoring()
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
      player?.volume = Float(seconds / fadeOut)
    }
  }

  private func pauseFromTimer() {
    let duration = originalTimerDuration

    player?.pause()
    player?.volume = 1.0

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

    AppLogger.player.info("Timer expired - playback paused")
  }

  private func formatExtendButtonTitle(for duration: TimeInterval) -> String {
    let formattedDuration = Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )
    return "Extend \(formattedDuration)"
  }

  private func extendTimer() {
    if originalTimerDuration > 0 {
      startSleepTimer(duration: originalTimerDuration)
      current = .preset(originalTimerDuration)

      player?.play()

      AppLogger.player.info("Timer extended by \(self.originalTimerDuration) seconds")
    }

    completedAlert = nil
  }

  private func resetTimerFromAlert() {
    completedAlert = nil
    current = .none
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil
    originalTimerDuration = 0

    ShakeDetector.shared.stopMonitoring()

    AppLogger.player.info("Timer reset from alert")
  }

  func pauseFromChapterTimer() {
    player?.pause()

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

    player?.play()

    AppLogger.player.info("Chapter timer extended by 1 chapter")

    completedAlert = nil
  }

  func onChapterChanged(current: Int, total: Int) {
    maxRemainingChapters = total - current - 1

    if case .chapters(let chapters) = self.current {
      if currentChapterIndex < current {
        if chapters > 1 {
          self.current = .chapters(chapters - 1)
        } else {
          pauseFromChapterTimer()
        }
      }
    }

    currentChapterIndex = current
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
    let duration = preferences.autoTimerDuration

    guard duration > 0,
      current == .none,
      isInAutoTimerWindow()
    else {
      return
    }

    current = .preset(duration)
    startSleepTimer(duration: duration)

    AppLogger.player.info("Auto-timer activated: \(duration) seconds")
  }

  func onShakeDetected() {
    guard preferences.shakeSensitivity.isEnabled, originalTimerDuration > 0 else { return }

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
