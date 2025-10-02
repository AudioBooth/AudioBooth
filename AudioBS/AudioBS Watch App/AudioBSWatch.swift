import Audiobookshelf
import SwiftUI

@main
struct AudioBSWatch: App {
  init() {
    _ = Audiobookshelf.shared
    _ = WatchConnectivityManager.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
