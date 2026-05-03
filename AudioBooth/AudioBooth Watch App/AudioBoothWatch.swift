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
    final class CustomHeaderDataLoader: DataLoading {
      private let inner: DataLoader

      init(inner: DataLoader) {
        self.inner = inner
      }

      func loadData(
        with request: URLRequest,
        didReceiveData: @escaping (Data, URLResponse) -> Void,
        completion: @escaping (Error?) -> Void
      ) -> any Cancellable {
        var request = request
        for (key, value) in WatchConnectivityManager.shared.customHeaders {
          request.setValue(value, forHTTPHeaderField: key)
        }
        return inner.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
      }
    }

    ImagePipeline.shared = ImagePipeline {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForResource = 300
      config.timeoutIntervalForRequest = 60
      config.allowsCellularAccess = true
      config.waitsForConnectivity = true
      config.allowsExpensiveNetworkAccess = true
      config.allowsConstrainedNetworkAccess = true
      config.urlCache = nil

      $0.dataLoader = CustomHeaderDataLoader(inner: DataLoader(configuration: config))
      $0.dataCache = try? DataCache(name: "me.jgrenier.audioBS.watch.images")
    }
  }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
        DownloadManager.shared.reconnectBackgroundSession(
          withIdentifier: urlSessionTask.sessionIdentifier
        )
        urlSessionTask.setTaskCompletedWithSnapshot(false)

      default:
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}
