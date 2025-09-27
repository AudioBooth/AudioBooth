import Audiobookshelf
import SwiftUI
import UIKit

@main
struct AudioBSApp: App {
  init() {
    DownloadManager.shared.cleanupOrphanedDownloads()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
