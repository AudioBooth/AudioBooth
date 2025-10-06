import NukeUI
import SwiftUI

@available(iOS 26.0, *)
struct MiniBookPlayer: View {
  private var playerManager: PlayerManager { .shared }

  @Environment(\.tabViewBottomAccessoryPlacement) var placement

  var player: BookPlayer.Model

  var body: some View {
    content
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .contentShape(Rectangle())
      .onTapGesture {
        playerManager.showFullPlayer()
      }
      .contextMenu {
        Button {
          playerManager.clearCurrent()
        } label: {
          Label("Stop", systemImage: "xmark.circle")
        }
      }
  }

  @ViewBuilder
  var content: some View {
    HStack {
      cover

      VStack(alignment: .leading, spacing: 2) {
        Text(player.title)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        Text(formatTimeRemaining(player.playbackProgress.totalTimeRemaining))
          .font(.caption)
          .foregroundColor(.secondary)
          .fontWeight(.medium)
      }

      button
    }
  }

  private var cover: some View {
    CoverImage(url: player.coverURL)
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private var button: some View {
    if placement != .inline {
      Button(action: player.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(Color.blue)
            .aspectRatio(1, contentMode: .fit)

          if player.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(0.7)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 10))
              .foregroundColor(.white)
          }
        }
      }
      .disabled(player.isLoading)
    }
  }

  private func formatTimeRemaining(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " remaining"
  }

}

struct LegacyMiniBookPlayer: View {
  private var playerManager: PlayerManager { .shared }

  var player: BookPlayer.Model

  var body: some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(.regularMaterial)
      .contentShape(Rectangle())
      .onTapGesture {
        playerManager.showFullPlayer()
      }
      .contextMenu {
        Button {
          playerManager.clearCurrent()
        } label: {
          Label("Stop", systemImage: "xmark.circle")
        }
      }
      .frame(maxHeight: 56)
  }

  @ViewBuilder
  var content: some View {
    HStack {
      cover

      VStack(alignment: .leading, spacing: 2) {
        Text(player.title)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .lineLimit(1)

        if let author = player.author {
          Text(author)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        Text(formatTimeRemaining(player.playbackProgress.totalTimeRemaining))
          .font(.caption)
          .foregroundColor(.secondary)
          .fontWeight(.medium)
      }

      Spacer()

      Button(action: player.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(Color.blue)
            .frame(width: 40, height: 40)

          if player.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(0.7)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 16))
              .foregroundColor(.white)
              .offset(x: player.isPlaying ? 0 : 2)
          }
        }
      }
      .disabled(player.isLoading)
    }
  }

  private var cover: some View {
    CoverImage(url: player.coverURL)
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func formatTimeRemaining(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " remaining"
  }
}

#Preview {
  VStack {
    Spacer()
    LegacyMiniBookPlayer(player: .mock)
  }
}
