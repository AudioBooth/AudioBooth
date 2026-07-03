import API
import AppIntents
import Logging
import Models
import PlayerIntents
import RevenueCat
import UIKit
import UserNotifications

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  static var orientationLock = UIInterfaceOrientationMask.all {
    didSet {
      for scene in UIApplication.shared.connectedScenes {
        if let windowScene = scene as? UIWindowScene {
          windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock))
          for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
          }
        }
      }
    }
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UISegmentedControl.appearance().apportionsSegmentWidthsByContent = true

    AppLogger.bootstrap()

    if !ProcessInfo.processInfo.isiOSAppOnMac {
      _ = CrashReporter.shared
    }

    Audiobookshelf.shared.onServerSwitched = { serverID, _ in
      do {
        try ModelContextProvider.shared.switchToServer(serverID)
      } catch {
        AppLogger.general.error("Failed to switch database: \(error.localizedDescription)")
      }
    }

    if let server = Audiobookshelf.shared.authentication.server {
      do {
        try ModelContextProvider.shared.switchToServer(server.id)
      } catch {
        AppLogger.general.error(
          "Failed to initialize database on app launch: \(error.localizedDescription)"
        )
      }
    }

    _ = WatchConnectivityManager.shared
    _ = SessionManager.shared
    _ = UserPreferences.shared
    _ = KeepOfflineManager.shared

    UNUserNotificationCenter.current().delegate = self

    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_AuBdFKRrOngbJsXGkkxDKGNbGRW")

    let player: PlayerManagerProtocol = PlayerManager.shared
    AppDependencyManager.shared.add(dependency: player)

    Task { @MainActor in
      await PlayerManager.shared.restoreLastPlayer()
      await Audiobookshelf.shared.authentication.checkServersHealth()
      await StorageManager.shared.cleanupUnusedDownloads()
    }

    #if !targetEnvironment(macCatalyst)
    endAllLiveActivities()
    #endif

    return true
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    DownloadManager.shared.handleBackgroundSessionEvents(
      identifier: identifier,
      completionHandler: completionHandler
    )
  }

  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}

extension AppDelegate {
  #if !targetEnvironment(macCatalyst)
  private func endAllLiveActivities() {
    Task {
      for activity in Activity<SleepTimerActivityAttributes>.activities {
        await activity.end(
          ActivityContent(state: activity.content.state, staleDate: nil),
          dismissalPolicy: .immediate
        )
      }
    }
  }
  #endif
}
