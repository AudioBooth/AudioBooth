import NukeUI
import SwiftUI

@available(iOS 26.0, *)
struct MiniBookPlayer: View, Equatable {
  private var playerManager: PlayerManager { .shared }

  @Environment(\.tabViewBottomAccessoryPlacement) var placement

  @ObservedObject var player: BookPlayer.Model

  static func == (lhs: MiniBookPlayer, rhs: MiniBookPlayer) -> Bool {
    lhs.player.id == rhs.player.id
      && lhs.player.playbackProgress.totalTimeRemaining
        == rhs.player.playbackProgress.totalTimeRemaining
      && lhs.player.isPlaying == rhs.player.isPlaying
      && lhs.player.isLoading == rhs.player.isLoading
  }

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
            .fill(Color.accentColor)
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
      .buttonStyle(.borderless)
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
    VStack(spacing: 0.0) {
      Divider()
      content
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      Divider()
    }
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

        Text(formatTimeRemaining(player.playbackProgress.totalTimeRemaining))
          .font(.caption)
          .foregroundColor(.secondary)
          .fontWeight(.medium)
      }

      Spacer()

      Button(action: player.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(Color.accentColor)
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
      .buttonStyle(.borderless)
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
  TabView {
    VStack(spacing: 0.0) {
      Spacer()
      LegacyMiniBookPlayer(player: .mock)
    }
    .tabItem {
      Image(systemName: "house")
      Text("Home")
    }

    Color.clear
      .tabItem {
        Image(systemName: "books.vertical.fill")
        Text("Library")
      }

    Color.clear
      .tabItem {
        Image(systemName: "square.stack.3d.up.fill")
        Text("Collections")
      }

    Color.clear
      .tabItem {
        Image(systemName: "person.crop.rectangle.stack")
        Text("Authors")
      }
  }
}
