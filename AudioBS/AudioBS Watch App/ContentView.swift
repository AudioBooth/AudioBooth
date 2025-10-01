import Combine
import SwiftUI

struct ContentView: View {
  @ObservedObject var connectivityManager = WatchConnectivityManager.shared
  @ObservedObject var playerManager = PlayerManager.shared
  @StateObject private var continueListeningModel = ContinueListeningViewModel()
  @StateObject private var nowPlayingModel = NowPlayingViewModel()

  var body: some View {
    NavigationStack {
      ContinueListeningView(model: continueListeningModel)
        .toolbar {
          if playerManager.hasActivePlayer || connectivityManager.hasActivePlayer {
            ToolbarItem(placement: .topBarTrailing) {
              NavigationLink {
                NowPlayingView(model: nowPlayingModel)
              } label: {
                Image(systemName: playerManager.hasActivePlayer ? "play.circle.fill" : "iphone")
              }
            }
          }
        }
    }
  }
}

#Preview {
  ContentView()
}
