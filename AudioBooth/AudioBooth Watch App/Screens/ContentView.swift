import SwiftUI

struct ContentView: View {
  @ObservedObject var connectivityManager = WatchConnectivityManager.shared
  @ObservedObject var playerManager = PlayerManager.shared

  @State private var player: PlayerView.Model?

  var body: some View {
    NavigationStack {
      ContinueListeningView(model: ContinueListeningViewModel())
        .toolbar {
          toolbar
        }
        .sheet(item: $player) { model in
          PlayerView(model: model)
        }
        .onChange(of: playerManager.isShowingFullPlayer) { _, newValue in
          if newValue, let model = playerManager.current {
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
    let hasIPhonePlayer = connectivityManager.currentBook != nil
    let isIPhonePlaying = hasIPhonePlayer && connectivityManager.isPlaying

    if playerManager.isPlayingOnWatch {
      return .watch
    }

    if hasWatchPlayer && !isIPhonePlaying {
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
          player = RemotePlayerModel()
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
