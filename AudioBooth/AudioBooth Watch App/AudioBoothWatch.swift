import Nuke
import SwiftUI

@main
struct AudioBoothWatch: App {
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
