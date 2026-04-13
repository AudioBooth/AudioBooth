import SwiftUI
import WatchKit

struct RemotePlayerView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var showOptions = false

  var body: some View {
    NowPlayingView()
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(
            action: {
              showOptions = true
            },
            label: {
              Image(systemName: "ellipsis")
            }
          )
        }
      }
      .sheet(isPresented: $showOptions) {
        NavigationStack {
          RemotePlayerOptionsSheet()
        }
      }
  }
}

#Preview {
  NavigationStack {
    RemotePlayerView()
  }
}
