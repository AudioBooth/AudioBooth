import AVFoundation
import Foundation
import Logging
import SwiftUI

final class TimerPickerSheetViewModel: TimerPickerSheet.Model {
  private weak var player: AVPlayer?
  private var sleepTimer: Timer?
  private var timerStartTime: Date?
  private var originalTimerDuration: TimeInterval = 0

  override init() {
    super.init()

    let totalMinutes = UserPreferences.shared.customTimerMinutes
    customHours = totalMinutes / 60
    customMinutes = totalMinutes % 60
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
      UserPreferences.shared.customTimerMinutes = totalMinutes
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
  }

  private func stopSleepTimer() {
    sleepTimer?.invalidate()
    sleepTimer = nil
    timerStartTime = nil
    originalTimerDuration = 0
  }

  private func updateSleepTimer() {
    switch current {
    case .preset(let seconds):
      if seconds > 1 {
        current = .preset(seconds - 1)
      } else {
        pauseFromTimer()
      }

    case .custom(let seconds):
      if seconds > 1 {
        current = .custom(seconds - 1)
      } else {
        pauseFromTimer()
      }

    case .none, .chapters:
      stopSleepTimer()
    }
  }

  private func pauseFromTimer() {
    let duration = originalTimerDuration

    player?.pause()

    if UserPreferences.shared.shakeToExtendTimer {
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
    AppLogger.player.info("Timer reset from alert")
  }

  func pauseFromChapterTimer() {
    player?.pause()

    if UserPreferences.shared.shakeToExtendTimer {
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

  func onChapterChanged(previous: Int, current: Int, total: Int) {
    maxRemainingChapters = total - current - 1

    if case .chapters(let chapters) = self.current {
      if previous < current {
        if chapters > 1 {
          self.current = .chapters(chapters - 1)
        } else {
          pauseFromChapterTimer()
        }
      }
    }
  }

}
