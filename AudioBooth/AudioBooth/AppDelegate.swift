import API
import UIKit
import WidgetKit

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
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    DownloadManager.shared.backgroundCompletionHandler = completionHandler
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    WidgetCenter.shared.reloadAllTimelines()
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    Task {
      if Audiobookshelf.shared.authentication.isAuthenticated {
        await SessionManager.shared.syncUnsyncedSessions()
      }
    }
  }

  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }
}
