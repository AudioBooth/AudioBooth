import AppIntents
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
  let entry: AudioBoothWidgetEntry
  let playbackState: PlaybackState
  @AppStorage("timeRemainingAdjustsWithSpeed", store: UserDefaults(suiteName: "group.me.jgrenier.audioBS"))
  var timeRemainingAdjustsWithSpeed: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let coverImage = entry.coverImage {
        Image(uiImage: coverImage)
          .resizable()
          .widgetAccentedRenderingMode(.desaturated)
          .aspectRatio(contentMode: .fill)
          .frame(width: 70, height: 70)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.gray)
          .frame(width: 70, height: 70)
          .overlay(
            Image(systemName: "book.fill")
              .foregroundStyle(.white.opacity(0.5))
          )
      }

      Spacer()

      Text(playbackState.title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer()

      HStack(spacing: 4) {
        playPauseButton

        let remaining = calculateTimeRemaining()
        Text(formatTime(remaining))
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.8))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var playPauseButton: some View {
    Group {
      if playbackState.isPlaying {
        Button(intent: PausePlaybackIntent()) {
          Image(systemName: "pause.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
      } else {
        Button(intent: ResumePlaybackIntent()) {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func calculateTimeRemaining() -> TimeInterval {
    var remaining = playbackState.duration - playbackState.currentTime
    if timeRemainingAdjustsWithSpeed {
      remaining /= Double(playbackState.playbackSpeed)
    }
    return remaining
  }

  private func formatTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }
}
