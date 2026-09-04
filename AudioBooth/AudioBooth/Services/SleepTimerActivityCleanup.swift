import BackgroundTasks
import Foundation
import Logging
import MediaPlayer
import PlayerIntents

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

final class SleepTimerActivityCleanup {
  static let shared = SleepTimerActivityCleanup()

  private let taskIdentifier = "me.jgrenier.AudioBS.dismiss-sleep-timer-activity"
  private let dismissalDelay: TimeInterval = 5 * 60

  private init() {
    registerBackgroundTask()
  }

  func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: dismissalDelay)

    do {
      try BGTaskScheduler.shared.submit(request)
      AppLogger.player.info(
        "Scheduled sleep timer Live Activity dismissal in \(self.dismissalDelay)s"
      )
    } catch let error as NSError {
      if error.code == 1 {
        AppLogger.player.warning(
          "Background tasks unavailable (Background App Refresh may be disabled). Live Activity will be dismissed on foreground instead."
        )
      } else {
        AppLogger.player.error("Failed to schedule Live Activity dismissal: \(error)")
      }
    }
  }

  func cancel() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    AppLogger.player.debug("Canceled scheduled sleep timer Live Activity dismissal")
  }

  private func registerBackgroundTask() {
    let success = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: taskIdentifier,
      using: nil
    ) { [weak self] task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self?.handleBackgroundTask(refreshTask)
    }

    if success {
      AppLogger.player.info("Registered Live Activity dismissal task: \(self.taskIdentifier)")
    } else {
      AppLogger.player.warning(
        "Failed to register Live Activity dismissal task: \(self.taskIdentifier)"
      )
    }
  }

  private func handleBackgroundTask(_ task: BGAppRefreshTask) {
    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }

    let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
    let playbackRate = nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0.0

    guard playbackRate == 0 else {
      AppLogger.player.info("Playback resumed, keeping sleep timer Live Activity")
      task.setTaskCompleted(success: true)
      return
    }

    Task {
      await endAllActivities()
      task.setTaskCompleted(success: true)
    }
  }

  #if !targetEnvironment(macCatalyst)
  private func endAllActivities() async {
    for activity in Activity<SleepTimerActivityAttributes>.activities {
      await activity.end(
        ActivityContent(state: activity.content.state, staleDate: nil),
        dismissalPolicy: .immediate
      )
    }
    AppLogger.player.info("Dismissed sleep timer Live Activity from background task")
  }
  #else
  private func endAllActivities() async {}
  #endif
}
