import API
import UIKit
import WidgetKit

class AppDelegate: NSObject, UIApplicationDelegate {
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
}
