import SwiftUI
import WatchKit

struct RemotePlayerView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var showOptions = false
  @State private var speedPickerModel: SpeedPickerSheet.Model = RemoteSpeedPickerModel()

  var body: some View {
    NowPlayingView()
      .overlay {
        VolumeControl(origin: .companion)
          .opacity(0.0)
          .allowsHitTesting(false)
          .focusable(true)
      }
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
          SpeedPickerSheet(model: speedPickerModel)
        }
      }
  }
}

#Preview {
  NavigationStack {
    RemotePlayerView()
  }
}
