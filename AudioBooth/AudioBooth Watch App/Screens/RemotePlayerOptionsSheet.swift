import MediaPlayer
import SwiftUI

struct RemotePlayerOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var playbackSpeed: Float = 1.0

  private let speeds: [Float] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]
  private let connectivityManager = WatchConnectivityManager.shared

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text("Speed")
          .font(.headline)

        Text(verbatim: "\(String(format: "%.1f", playbackSpeed))×")
          .font(.title2)
          .fontWeight(.medium)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
          ForEach(speeds, id: \.self) { speed in
            speedButton(for: speed)
          }
        }
        .padding(.horizontal)
      }
      .padding(.top)
    }
    .navigationTitle("Options")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      loadCurrentSpeed()
    }
  }

  @ViewBuilder
  func speedButton(for speed: Float) -> some View {
    let isSelected = abs(playbackSpeed - speed) < 0.01

    Button {
      playbackSpeed = speed
      connectivityManager.changePlaybackRate(speed)
      dismiss()
    } label: {
      VStack(spacing: 4) {
        Text(String(format: "%.1f", speed))
          .font(.body)
          .fontWeight(isSelected ? .bold : .regular)

        if speed == 1.0 {
          Text("DEFAULT")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.orange)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.orange : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }

  private func loadCurrentSpeed() {
    playbackSpeed = connectivityManager.playbackRate
  }
}

#Preview {
  NavigationStack {
    RemotePlayerOptionsSheet()
  }
}
