import SwiftUI
import WatchKit

struct RemotePlayerView: View {
  @State private var showOptions = false
  @State private var speedPickerModel: SpeedPickerSheet.Model = RemoteSpeedPickerModel()
  @State private var timerModel: TimerPickerSheet.Model = RemoteTimerPickerModel()

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
          List {
            Button(action: {
              speedPickerModel.isPresented = true
              showOptions = false
            }) {
              Label(
                "Speed (\(speedPickerModel.speed.formatted(.number.precision(.fractionLength(0...2))))×)",
                systemImage: "gauge.with.dots.needle.33percent"
              )
            }

            Button(action: {
              timerModel.isPresented = true
              showOptions = false
            }) {
              Label("Sleep Timer", systemImage: "moon.zzz")
            }
          }
          .navigationTitle("Options")
          .navigationBarTitleDisplayMode(.inline)
        }
      }
      .sheet(isPresented: $speedPickerModel.isPresented) {
        NavigationStack {
          SpeedPickerSheet(model: speedPickerModel)
        }
      }
      .sheet(isPresented: $timerModel.isPresented) {
        NavigationStack {
          TimerPickerSheet(model: timerModel)
        }
      }
  }
}

#Preview {
  NavigationStack {
    RemotePlayerView()
  }
}
