import Combine
import NukeUI
import SwiftUI

struct NowPlayingView: View {
  @StateObject var model: Model

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        CoverArtView(coverURL: model.coverURL)

        TitleAuthorView(title: model.title, author: model.author)

        PlaybackProgressView(
          progress: model.progress,
          current: model.current,
          remaining: model.remaining,
          totalTimeRemaining: model.totalTimeRemaining
        )

        PlaybackControlsView(
          isPlaying: model.isPlaying,
          onTogglePlayback: { model.togglePlayback() },
          onSkipBackward: { model.skipBackward() },
          onSkipForward: { model.skipForward() }
        )

        PlaybackSpeedView(playbackSpeed: model.playbackSpeed)
      }
      .padding()
    }
    .navigationTitle("Playing")
  }
}

extension NowPlayingView {
  private struct CoverArtView: View {
    let coverURL: URL?

    var body: some View {
      if let coverURL {
        LazyImage(url: coverURL) { state in
          if let image = state.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Color.gray
          }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
  }
}

extension NowPlayingView {
  private struct TitleAuthorView: View {
    let title: String
    let author: String

    var body: some View {
      VStack(spacing: 4) {
        Text(title)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)

        if !author.isEmpty {
          Text(author)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }
}

extension NowPlayingView {
  struct PlaybackProgressView: View {
    let progress: Double
    let current: Double
    let remaining: Double
    let totalTimeRemaining: Double

    var body: some View {
      VStack(spacing: 4) {
        ProgressView(value: progress, total: 1.0)

        HStack {
          Text(formatTime(current))
            .font(.caption2)
            .foregroundStyle(.secondary)

          Spacer()

          Text("-\(formatTime(remaining))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()

        Text(formatTimeRemaining(totalTimeRemaining))
          .font(.caption2)
          .fontWeight(.medium)
      }
    }

    private func formatTime(_ seconds: Double) -> String {
      Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    private func formatTimeRemaining(_ duration: Double) -> String {
      Duration.seconds(duration).formatted(
        .units(
          allowed: [.hours, .minutes],
          width: .narrow
        )
      ) + " left"
    }
  }
}

extension NowPlayingView {
  private struct PlaybackControlsView: View {
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void

    var body: some View {
      HStack(spacing: 20) {
        Button(action: onSkipBackward) {
          Image(systemName: "gobackward.30")
            .font(.title2)
        }
        .buttonStyle(.plain)

        Button(action: onTogglePlayback) {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.title)
        }
        .buttonStyle(.plain)

        Button(action: onSkipForward) {
          Image(systemName: "goforward.30")
            .font(.title2)
        }
        .buttonStyle(.plain)
      }
      .padding(.top, 8)
    }
  }
}

extension NowPlayingView {
  private struct PlaybackSpeedView: View {
    let playbackSpeed: Float

    var body: some View {
      if playbackSpeed != 1.0 {
        Text("\(playbackSpeed, specifier: "%.1f")x")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

extension NowPlayingView {
  @Observable class Model: ObservableObject {
    var isPlaying: Bool
    var progress: Double
    var current: Double
    var remaining: Double
    var total: Double
    var totalTimeRemaining: Double
    var bookID: String
    var title: String
    var author: String
    var coverURL: URL?
    var playbackSpeed: Float
    var hasActivePlayer: Bool

    func togglePlayback() {}
    func skipBackward() {}
    func skipForward() {}

    init(
      isPlaying: Bool = false,
      progress: Double = 0,
      current: Double = 0,
      remaining: Double = 0,
      total: Double = 0,
      totalTimeRemaining: Double = 0,
      bookID: String = "",
      title: String = "",
      author: String = "",
      coverURL: URL? = nil,
      playbackSpeed: Float = 1.0,
      hasActivePlayer: Bool = false
    ) {
      self.isPlaying = isPlaying
      self.progress = progress
      self.current = current
      self.remaining = remaining
      self.total = total
      self.totalTimeRemaining = totalTimeRemaining
      self.bookID = bookID
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.playbackSpeed = playbackSpeed
      self.hasActivePlayer = hasActivePlayer
    }
  }
}

#Preview {
  NavigationStack {
    NowPlayingView(
      model: NowPlayingView.Model(
        isPlaying: true,
        progress: 0.45,
        current: 1800,
        remaining: 2200,
        total: 4000,
        totalTimeRemaining: 38000,
        bookID: "1",
        title: "The Lord of the Rings",
        author: "J.R.R. Tolkien",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        playbackSpeed: 1.2,
        hasActivePlayer: true
      )
    )
  }
}
