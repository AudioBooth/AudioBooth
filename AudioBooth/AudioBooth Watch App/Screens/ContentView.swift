import SwiftUI

struct ContentView: View {
  @ObservedObject var connectivityManager = WatchConnectivityManager.shared
  @ObservedObject var playerManager = PlayerManager.shared

  @State private var player: PlayerView.Model?
  @State private var showRemotePlayer = false

  var body: some View {
    NavigationStack {
      ContinueListeningView(model: ContinueListeningViewModel())
        .toolbar {
          toolbar
        }
        .sheet(item: $player) { model in
          PlayerView(model: model)
        }
        .sheet(isPresented: $showRemotePlayer) {
          NavigationStack {
            RemotePlayerView()
          }
        }
        .onChange(of: playerManager.isShowingFullPlayer) { _, newValue in
          if newValue, let model = playerManager.presented {
            self.player = model
          } else if !newValue {
            self.player = nil
          }
        }
    }
  }

  enum PlayerButton {
    case watch
    case iphone
    case none
  }

  var activePlayerButton: PlayerButton {
    let hasWatchPlayer = playerManager.current is BookPlayerModel
    let hasIPhonePlayer = connectivityManager.hasCurrentBook

    if playerManager.isPlayingOnWatch {
      return .watch
    }

    if hasWatchPlayer && !hasIPhonePlayer {
      return .watch
    }

    if hasIPhonePlayer {
      return .iphone
    }

    return .none
  }

  @ToolbarContentBuilder
  var toolbar: some ToolbarContent {
    switch activePlayerButton {
    case .watch:
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          player = playerManager.current
        } label: {
          Image(systemName: "applewatch")
        }
      }
    case .iphone:
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          playerManager.clearCurrent()
          showRemotePlayer = true
        } label: {
          Image(systemName: "iphone")
        }
      }
    case .none:
      ToolbarItem(placement: .topBarTrailing) {
        EmptyView()
      }
    }
  }
}

#Preview {
  ContentView()
}
