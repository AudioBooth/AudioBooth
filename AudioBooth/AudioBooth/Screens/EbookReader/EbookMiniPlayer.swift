import Combine
import SwiftUI

struct EbookMiniPlayer: View {
  @ObservedObject var player: BookPlayer.Model
  @Binding var scrubBarFrame: CGRect
  let onTap: () -> Void

  @ObservedObject private var preferences = UserPreferences.shared

  @State private var width: CGFloat = 0
  @State private var lastDragLocationX: CGFloat?
  @State private var scrubbingSpeed: PlaybackProgressView.ScrubbingSpeed = .normal

  private var progress: PlaybackProgressView.Model { player.playbackProgress }

  var body: some View {
    HStack(spacing: 8) {
      if progress.isDragging {
        scrubber
      } else {
        Cover(url: player.coverURL)

        info

        controls
      }
    }
    .frame(height: 36)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .contentShape(.rect)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onTapGesture {
      Haptics.impact(.medium)
      onTap()
    }
    .gesture(scrubGesture)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private var info: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(player.title)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .lineLimit(1)

      Text(progress.totalTimeRemaining.formattedTimeRemaining)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityLabel(progress.totalTimeRemaining.accessibilityTimeRemaining)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var scrubber: some View {
    VStack(spacing: 4) {
      Capsule()
        .fill(.secondary.opacity(0.3))
        .overlay(alignment: .leading) {
          Capsule()
            .fill(.tint)
            .frame(width: max(0, (width - 24) * progress.progress))
        }
        .frame(height: 6)
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .global)
        } action: {
          scrubBarFrame = $0
        }

      HStack {
        Text(verbatim: formatTime(progress.current))
          .foregroundStyle(.secondary)

        Group {
          if let label = scrubbingSpeed.label {
            Text(label)
          } else {
            Text(progress.totalTimeRemaining.formattedTimeRemaining)
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .center)

        Text(verbatim: "-\(formatTime(progress.remaining))")
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .monospacedDigit()
    }
  }

  private var controls: some View {
    HStack(spacing: 4) {
      controlButton(systemImage: "gobackward.\(Int(preferences.skipBackwardInterval))") {
        Haptics.impact(.light)
        player.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
      }
      .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")

      playButton
        .frame(width: 32, height: 32)
        .padding(.horizontal, 4)

      controlButton(systemImage: "goforward.\(Int(preferences.skipForwardInterval))") {
        Haptics.impact(.light)
        player.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
      }
      .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")
    }
    .foregroundStyle(.primary)
    .buttonStyle(.borderless)
  }

  private var playButton: some View {
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
            .font(.system(size: 14))
            .foregroundColor(.white)
        }
      }
    }
    .disabled(player.isLoading)
    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
  }

  private func controlButton(systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 18))
        .frame(width: 36, height: 36)
    }
  }

  private var scrubGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.3)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .onChanged { value in
        guard case .second(true, let drag) = value else { return }

        if !progress.isDragging {
          progress.isDragging = true
          Haptics.selection()
        }

        guard let drag else { return }

        let speed = PlaybackProgressView.ScrubbingSpeed(verticalOffset: -drag.translation.height)
        if speed != scrubbingSpeed {
          scrubbingSpeed = speed
          Haptics.selection()
        }

        if let lastDragLocationX, width > 0 {
          let delta = Double((drag.location.x - lastDragLocationX) / width) * speed.rate
          let newProgress = min(max(0, progress.progress + delta), 1)
          let total = progress.current + progress.remaining
          progress.progress = newProgress
          progress.current = total * newProgress
          progress.remaining = total - progress.current
        }

        lastDragLocationX = drag.location.x
      }
      .onEnded { _ in
        guard progress.isDragging else { return }
        progress.onProgressChanged(progress.progress)
        progress.isDragging = false
        lastDragLocationX = nil
        scrubbingSpeed = .normal
      }
  }

  private func formatTime(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
  }
}
