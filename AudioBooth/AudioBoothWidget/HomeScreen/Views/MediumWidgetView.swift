import AppIntents
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
  let entry: AudioBoothWidgetEntry
  let playbackState: PlaybackState
  @AppStorage("timeRemainingAdjustsWithSpeed", store: UserDefaults(suiteName: "group.me.jgrenier.audioBS"))
  var timeRemainingAdjustsWithSpeed: Bool = true

  var body: some View {
    HStack(spacing: 12) {
      if let coverImage = entry.coverImage {
        Image(uiImage: coverImage)
          .resizable()
          .widgetAccentedRenderingMode(.desaturated)
          .aspectRatio(contentMode: .fill)
          .frame(width: 120, height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.gray)
          .frame(width: 120, height: 120)
          .overlay(
            Image(systemName: "book.fill")
              .font(.system(size: 40))
              .foregroundStyle(.white.opacity(0.5))
          )
      }

      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(playbackState.title)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .lineLimit(2)

          Text(playbackState.author)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
        }

        VStack(alignment: .leading, spacing: 6) {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(height: 6)

              RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(
                  width: geometry.size.width * playbackState.progress,
                  height: 6
                )
            }
          }
          .frame(height: 6)

          let remaining = calculateTimeRemaining()
          Text(formatTime(remaining))
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.8))
        }

        Spacer()

        HStack(spacing: 12) {
          playPauseButton

          Spacer()
        }
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
