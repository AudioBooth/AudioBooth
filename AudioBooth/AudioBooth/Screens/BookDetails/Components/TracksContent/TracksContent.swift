import Models
import SwiftUI

struct TracksContent: View {
  @Environment(\.appTheme) var theme
  let model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(model.tracks, id: \.index) { track in
        VStack(alignment: .leading, spacing: 8) {
          Text(track.filename ?? "Track \(track.index)")
            .font(.caption)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .leading, spacing: 2) {
            if let codec = track.codec {
              Text("**Codec:** \(codec)")
            }

            if let bitRate = track.bitRate {
              Text("**Bitrate:** \(bitRate / 1000) kbps")
            }

            if let channel = track.channels {
              Text("**Channel:** \(channel) (\(track.channelLayout ?? ""))")
            }

            if let size = track.size {
              Text(
                "**Size:** \(size.formatted(.byteCount(style: .file, allowedUnits: [.kb, .mb, .gb])))"
              )
            }

            Text("**Duration:** \(formatDuration(track.duration))")
          }
          .font(.caption2)
          .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
    .padding()
    .background(theme.colors.background.card)
    .cornerRadius(8)
  }

  private func formatDuration(_ seconds: Double) -> String {
    if seconds < 3600 {
      Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    } else {
      Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
    }
  }
}

extension TracksContent {
  struct Model {
    let tracks: [Track]
  }
}
