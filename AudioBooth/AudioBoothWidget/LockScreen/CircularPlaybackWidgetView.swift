import AppIntents
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

struct CircularPlaybackWidgetView: View {
  let entry: AudioBoothWidgetEntry

  var body: some View {
    if let playbackState = entry.playbackState {
      playbackView(playbackState: playbackState)
    } else {
      emptyStateView
    }
  }

  private func playbackView(playbackState: PlaybackState) -> some View {
    ZStack {
      AccessoryWidgetBackground()

      Gauge(value: playbackState.progress, in: 0...1) {
        Text("\(Int(playbackState.progress * 100))%")
      } currentValueLabel: {
        playPauseButton(isPlaying: playbackState.isPlaying)
      }
      .gaugeStyle(.accessoryCircular)
    }
  }

  private func playPauseButton(isPlaying: Bool) -> some View {
    Group {
      if isPlaying {
        Button(intent: PausePlaybackIntent()) {
          Image(systemName: "pause.fill")
            .font(.subheadline)
        }
        .buttonStyle(.plain)
      } else {
        Button(intent: ResumePlaybackIntent()) {
          Image(systemName: "play.fill")
            .font(.subheadline)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var emptyStateView: some View {
    ZStack {
      AccessoryWidgetBackground()
      Image(systemName: "book.fill")
        .font(.caption)
    }
  }
}
