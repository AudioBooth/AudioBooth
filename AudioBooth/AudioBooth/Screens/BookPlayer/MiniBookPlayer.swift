import SwiftUI

@available(iOS 26.0, *)
struct MiniBookPlayer: View, Equatable {
  @ObservedObject private var playerManager = PlayerManager.shared

  @Environment(\.tabViewBottomAccessoryPlacement) var placement
  @Environment(\.horizontalSizeClass) var horizontalSizeClass

  @ObservedObject var player: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared
  var namespace: Namespace.ID

  @State private var width: CGFloat = 0

  static func == (lhs: MiniBookPlayer, rhs: MiniBookPlayer) -> Bool {
    lhs.player.id == rhs.player.id
      && lhs.player.playbackProgress.totalTimeRemaining
        == rhs.player.playbackProgress.totalTimeRemaining
      && lhs.player.isPlaying == rhs.player.isPlaying
      && lhs.player.isLoading == rhs.player.isLoading
      && lhs.player.speed.value == rhs.player.speed.value
      && lhs.player.timer.current == rhs.player.timer.current
  }

  var body: some View {
    content
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .contentShape(Rectangle())
      .onTapGesture {
        Haptics.impact(.medium)
        playerManager.showFullPlayer()
      }
      .contextMenu {
        Button {
          playerManager.clearCurrent()
        } label: {
          Label("Stop", systemImage: "xmark.circle")
        }
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
  }

  @ViewBuilder
  var content: some View {
    if placement == .expanded, horizontalSizeClass == .regular, width >= 500 {
      HStack(spacing: 16) {
        playbackControls

        HStack {
          cover
          info
        }

        queueButton(iconSize: 18, frameSize: 36)
      }
    } else {
      HStack {
        cover
        info
        buttons
      }
    }
  }

  private var info: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(player.title)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundColor(.primary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(player.playbackProgress.totalTimeRemaining.formattedTimeRemaining)
        .font(.caption)
        .foregroundColor(.secondary)
        .fontWeight(.medium)
        .accessibilityLabel(player.playbackProgress.totalTimeRemaining.accessibilityTimeRemaining)
    }
  }

  private var cover: some View {
    Cover(url: player.coverURL)
      .zoomTransitionSource(id: "player", in: namespace)
  }

  private var playbackControls: some View {
    HStack(spacing: 4) {
      Button {
        Haptics.impact(.soft)
        player.speed.isPresented = true
      } label: {
        Text(verbatim: "\(player.speed.value.formatted(.number.precision(.fractionLength(0...2))))×")
          .font(.subheadline)
          .fontWeight(.medium)
          .frame(height: 36)
          .padding(.horizontal, 6)
      }
      .accessibilityLabel("Speed")

      controlButton(systemImage: "gobackward.\(Int(preferences.skipBackwardInterval))") {
        Haptics.impact(.light)
        player.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
      }
      .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")

      playButton(iconSize: 14)
        .frame(width: 32, height: 32)
        .padding(.horizontal, 4)

      controlButton(systemImage: "goforward.\(Int(preferences.skipForwardInterval))") {
        Haptics.impact(.light)
        player.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
      }
      .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")

      controlButton(systemImage: PlayerControl.timer.systemImage) {
        Haptics.impact(.soft)
        player.timer.isPresented = true
      }
      .foregroundStyle(player.timer.current == .none ? Color.secondary : Color.accentColor)
      .accessibilityLabel("Timer")
    }
    .foregroundStyle(.primary)
    .buttonStyle(.borderless)
  }

  private func playButton(iconSize: CGFloat) -> some View {
    Button {
      Haptics.impact(.medium)
      player.onTogglePlaybackTapped()
    } label: {
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
            .font(.system(size: iconSize))
            .foregroundColor(.white)
        }
      }
    }
    .disabled(player.isLoading)
    .buttonStyle(.borderless)
    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
  }

  private func queueButton(iconSize: CGFloat, frameSize: CGFloat? = nil) -> some View {
    Button {
      player.isQueuePresented = true
    } label: {
      Image(systemName: "list.bullet")
        .font(.system(size: iconSize))
        .foregroundColor(playerManager.queue.isEmpty ? .secondary : .primary)
        .frame(width: frameSize, height: frameSize)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("Queue")
  }

  private func controlButton(systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 18))
        .frame(width: 36, height: 36)
    }
  }

  @ViewBuilder
  private var buttons: some View {
    if placement != .inline {
      HStack(spacing: 8) {
        playButton(iconSize: 10)

        queueButton(iconSize: 12)
      }
    }
  }
}

struct LegacyMiniBookPlayer: View {
  private var playerManager: PlayerManager { .shared }

  var player: BookPlayer.Model
  var namespace: Namespace.ID

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
      Haptics.impact(.medium)
      playerManager.showFullPlayer()
    }
    .frame(maxHeight: 56)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  @ViewBuilder
  var content: some View {
    HStack {
      cover

      VStack(alignment: .leading, spacing: 2) {
        Text(player.title)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundColor(.primary)
          .lineLimit(1)

        Text(player.playbackProgress.totalTimeRemaining.formattedTimeRemaining)
          .font(.caption)
          .foregroundColor(.secondary)
          .fontWeight(.medium)
          .accessibilityLabel(player.playbackProgress.totalTimeRemaining.accessibilityTimeRemaining)
      }

      Spacer()

      HStack(spacing: 12) {
        Button(action: {
          Haptics.impact(.medium)
          player.onTogglePlaybackTapped()
        }) {
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
            }
          }
        }
        .disabled(player.isLoading)
        .buttonStyle(.borderless)

        Button {
          player.isQueuePresented = true
        } label: {
          Image(systemName: "list.bullet")
            .font(.system(size: 16))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
      }
    }
  }

  private var cover: some View {
    Cover(url: player.coverURL)
      .zoomTransitionSource(id: "player", in: namespace)
  }
}

#Preview {
  @Previewable @Namespace var namespace

  TabView {
    VStack(spacing: 0.0) {
      Spacer()
      LegacyMiniBookPlayer(player: .mock, namespace: namespace)
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
