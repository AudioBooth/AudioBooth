import API
import ActivityKit
import AppIntents
import Logging
import Models
import PlayerIntents
import RevenueCat
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
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

    LegacyMigration.migrateIfNeeded()

    Audiobookshelf.shared.onServerSwitched = { serverID, serverURL in
      do {
        try ModelContextProvider.shared.switchToServer(serverID, serverURL: serverURL)
      } catch {
        AppLogger.general.error("Failed to switch database: \(error.localizedDescription)")
      }
    }

    if let server = Audiobookshelf.shared.authentication.server {
      do {
        try ModelContextProvider.shared.switchToServer(server.id, serverURL: server.baseURL)
      } catch {
        AppLogger.general.error(
          "Failed to initialize database on app launch: \(error.localizedDescription)"
        )
      }
    }

    LegacyMigration.migrateTrackPaths()

    _ = WatchConnectivityManager.shared
    _ = SessionManager.shared
    _ = UserPreferences.shared

    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_AuBdFKRrOngbJsXGkkxDKGNbGRW")

    let player: PlayerManagerProtocol = PlayerManager.shared
    AppDependencyManager.shared.add(dependency: player)

    Task { @MainActor in
      await PlayerManager.shared.restoreLastPlayer()
      await Audiobookshelf.shared.authentication.checkServersHealth()
      await StorageManager.shared.cleanupUnusedDownloads()
    }

    endAllLiveActivities()

    return true
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    DownloadManager.shared.backgroundCompletionHandler = completionHandler
  }

  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }

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
}
