import API
import Nuke
import SwiftUI
import WatchKit

@main
struct AudioBoothWatch: App {
  @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate

  init() {
    ImagePipeline.shared = .watch(customHeaders: Audiobookshelf.shared.authentication.server?.customHeaders)
    _ = WatchConnectivityManager.shared
    DownloadManager.shared.start()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

extension ImagePipeline {
  nonisolated private static let dataCache = try? DataCache(name: "me.jgrenier.audioBS.watch.images")

  nonisolated static func watch(customHeaders: [String: String]?) -> ImagePipeline {
    ImagePipeline {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForResource = 300
      config.timeoutIntervalForRequest = 60
      config.allowsCellularAccess = true
      config.waitsForConnectivity = true
      config.allowsExpensiveNetworkAccess = true
      config.allowsConstrainedNetworkAccess = true
      config.urlCache = nil
      config.httpAdditionalHeaders = customHeaders

      $0.dataLoader = DataLoader(configuration: config)
      $0.dataCache = dataCache
    }
  }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
  func applicationDidBecomeActive() {
    DownloadManager.shared.applicationDidBecomeActive()
  }

  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
        DownloadManager.shared.reconnectBackgroundSession(
          withIdentifier: urlSessionTask.sessionIdentifier
        ) {
          urlSessionTask.setTaskCompletedWithSnapshot(false)
        }

      case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
        WatchConnectivityManager.shared.handleBackgroundTask(connectivityTask)

      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}
