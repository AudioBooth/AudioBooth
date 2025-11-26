import Nuke
import SwiftUI
import WatchKit

@main
struct AudioBoothWatch: App {
  @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate

  init() {
    configureImagePipeline()
    DownloadManager.shared.cleanupOrphanedDownloads()
    _ = WatchConnectivityManager.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }

  private func configureImagePipeline() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForResource = 300
    config.timeoutIntervalForRequest = 60
    config.allowsCellularAccess = true
    config.waitsForConnectivity = true
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true

    let dataLoader = DataLoader(configuration: config)
    let pipeline = ImagePipeline(configuration: .init(dataLoader: dataLoader))
    ImagePipeline.shared = pipeline
  }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
        DownloadManager.shared.reconnectBackgroundSession(
          withIdentifier: urlSessionTask.sessionIdentifier)
        urlSessionTask.setTaskCompletedWithSnapshot(false)

      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}
