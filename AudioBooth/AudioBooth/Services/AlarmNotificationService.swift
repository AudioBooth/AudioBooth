import Foundation
import UserNotifications

final class AlarmNotificationService {
  private let center = UNUserNotificationCenter.current()
  private let identifier = "playerAlarm"
  let soundFileName = "alarm_tone.wav"

  init() {}

  func requestAuthorizationIfNeeded() async -> Bool {
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
      return true
    }

    if settings.authorizationStatus == .denied {
      return false
    }

    do {
      return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    } catch {
      return false
    }
  }

  func schedule(triggerDate: Date) async {
    cancel()

    let interval = max(1, triggerDate.timeIntervalSinceNow)
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Alarm")
    content.body = String(localized: "AudioBooth alarm")
    content.sound = UNNotificationSound(
      named: UNNotificationSoundName(rawValue: soundFileName)
    )

    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    )

    try? await center.add(request)
  }

  func cancel() {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }
}
