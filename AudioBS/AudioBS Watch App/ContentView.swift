import Combine
import SwiftUI

struct ContentView: View {
  @ObservedObject var connectivityManager = WatchConnectivityManager.shared
  @StateObject private var continueListeningModel = ContinueListeningViewModel()
  @StateObject private var nowPlayingModel = NowPlayingViewModel()

  var body: some View {
    NavigationStack {
      ContinueListeningView(model: continueListeningModel)
        .toolbar {
          if connectivityManager.hasActivePlayer {
            ToolbarItem(placement: .topBarTrailing) {
              NavigationLink {
                NowPlayingView(model: nowPlayingModel)
              } label: {
                Image(systemName: "iphone")
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
