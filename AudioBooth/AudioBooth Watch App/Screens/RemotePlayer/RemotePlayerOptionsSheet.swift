import Combine
import SwiftUI

struct RemotePlayerOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var connectivityManager = WatchConnectivityManager.shared

  private let speeds: [Float] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text("Speed")
          .font(.headline)

        Text(verbatim: "\(connectivityManager.playbackRate.formatted(.number.precision(.fractionLength(0...2))))×")
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
  }

  @ViewBuilder
  func speedButton(for speed: Float) -> some View {
    let isSelected = abs(connectivityManager.playbackRate - speed) < 0.01

    Button {
      connectivityManager.playbackRate = speed
      connectivityManager.changePlaybackRate(speed)
      dismiss()
    } label: {
      VStack(spacing: 4) {
        Text(speed, format: .number.precision(.fractionLength(0...2)))
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

}

#Preview {
  NavigationStack {
    RemotePlayerOptionsSheet()
  }
}
