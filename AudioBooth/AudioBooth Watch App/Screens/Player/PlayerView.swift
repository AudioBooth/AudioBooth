import Combine
import NukeUI
import SwiftUI

struct PlayerView: View {
  @Environment(\.dismiss) private var dismiss

  private var playerManager: PlayerManager { .shared }

  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 6) {
      Button(action: {
        if model.options.downloadState != .downloaded {
          model.onDownloadTapped()
        }
      }) {
        Cover(
          url: model.coverURL,
          state: model.options.downloadState
        )
      }
      .buttonStyle(.plain)
      .allowsHitTesting(model.options.downloadState == .notDownloaded)

      content

      Playback(
        current: model.chapterTitle != nil ? model.chapterCurrent : model.current,
        remaining: model.chapterTitle != nil ? model.chapterRemaining : model.remaining,
        totalTimeRemaining: model.totalTimeRemaining
      )
      .padding(.bottom, 12)
    }
    .padding(.top, -16)
    .toolbar {
      toolbar
    }
    .sheet(isPresented: $model.options.isPresented) {
      PlayerOptionsSheet(model: model.options)
    }
    .sheet(
      isPresented: Binding(
        get: { model.chapters?.isPresented ?? false },
        set: { newValue in model.chapters?.isPresented = newValue }
      )
    ) {
      if let chapters = Binding($model.chapters) {
        ChapterPickerSheet(model: chapters)
      }
    }
    .onDisappear {
      playerManager.isShowingFullPlayer = false
    }
    .overlay {
      if model.isLocal {
        VolumeView()
      }
    }
    .alert(
      "Playback Error",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") {
        model.errorMessage = nil
      }
    } message: {
      if let errorMessage = model.errorMessage {
        Text(errorMessage)
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Button(
        action: {
          dismiss()
        },
        label: {
          Image(systemName: "xmark")
        }
      )
      .tint(.primary)
    }

    if !model.options.isHidden {
      ToolbarItem(placement: .topBarTrailing) {
        Button(
          action: {
            model.options.isPresented = true
          },
          label: {
            Image(systemName: "ellipsis")
          }
        )
        .tint(.primary)
      }
    }

    ToolbarItemGroup(placement: .bottomBar) {
      Button(
        action: model.skipBackward,
        label: {
          Image(systemName: "gobackward.30")
        }
      )
      .disabled(model.playbackState != .ready)
      .tint(.primary)

      playButton
        .frame(width: 44, height: 44)
        .overlay { progress }
        .controlSize(.large)
        .tint(.primary)

      Button(
        action: model.skipForward,
        label: {
          Image(systemName: "goforward.30")
        }
      )
      .disabled(model.playbackState != .ready)
      .tint(.primary)
    }

  }

  @ViewBuilder
  var playButton: some View {
    switch model.playbackState {
    case .loading:
      ProgressView()
        .controlSize(.regular)
    case .ready:
      if #available(watchOS 11.0, *) {
        Button(
          action: model.togglePlayback,
          label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          }
        )
        .handGestureShortcut(.primaryAction)
      } else {
        Button(
          action: model.togglePlayback,
          label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          }
        )
      }
    case .error(let retryable):
      if retryable {
        Button(
          action: model.retry,
          label: {
            Image(systemName: "arrow.clockwise")
          }
        )
      } else {
        Button(
          action: {},
          label: {
            Image(systemName: "exclamationmark.triangle.fill")
          }
        )
        .disabled(true)
      }
    }
  }

  var progress: some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.5), lineWidth: 2)

      Circle()
        .trim(from: 0, to: model.progress)
        .stroke(
          Color.white,
          style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
  }

  private var content: some View {
    Marquee {
      HStack {
        Text(model.title)
          .font(.caption2)
          .fontWeight(.medium)
          .multilineTextAlignment(.center)

        if let author = model.author {
          Text("by \(author)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

extension PlayerView {
  struct Playback: View {
    let current: Double
    let remaining: Double
    let totalTimeRemaining: Double

    var body: some View {
      HStack(alignment: .bottom) {
        Text(formatTime(current))
          .font(.system(size: 10))

        Text("\(formatTimeRemaining(totalTimeRemaining))")
          .font(.system(size: 11))
          .frame(maxWidth: .infinity, alignment: .center)

        Text("-\(formatTime(remaining))")
          .font(.system(size: 10))
      }
      .foregroundStyle(.secondary)
      .monospacedDigit()
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

extension PlayerView {
  enum PlaybackState: Equatable {
    case loading
    case ready
    case error(retryable: Bool)
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    var playbackState: PlaybackState = .loading
    var isLocal: Bool = false
    var errorMessage: String?

    var isPlaying: Bool
    var progress: Double
    var current: Double
    var remaining: Double
    var totalTimeRemaining: Double

    var chapterTitle: String?
    var chapterProgress: Double = 0
    var chapterCurrent: Double = 0
    var chapterRemaining: Double = 0

    var title: String
    var author: String?
    var coverURL: URL?
    var chapters: ChapterPickerSheet.Model?
    var options: PlayerOptionsSheet.Model

    func togglePlayback() {}
    func skipBackward() {}
    func skipForward() {}
    func onDownloadTapped() {}
    func stop() {}
    func retry() {}

    init(
      isPlaying: Bool = false,
      playbackState: PlaybackState = .ready,
      isLocal: Bool = true,
      progress: Double = 0,
      current: Double = 0,
      remaining: Double = 0,
      totalTimeRemaining: Double = 0,
      title: String = "",
      author: String? = nil,
      coverURL: URL? = nil,
      chapters: ChapterPickerSheet.Model? = nil
    ) {
      self.isPlaying = isPlaying
      self.playbackState = playbackState
      self.isLocal = isLocal
      self.progress = progress
      self.current = current
      self.remaining = remaining
      self.totalTimeRemaining = totalTimeRemaining
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.chapters = chapters
      self.options = PlayerOptionsSheet.Model(
        hasChapters: chapters != nil,
        downloadState: .downloaded
      )
    }
  }
}

#Preview {
  NavigationStack {
    PlayerView(
      model: PlayerView.Model(
        isPlaying: true,
        progress: 0.45,
        current: 1800,
        remaining: 2200,
        totalTimeRemaining: 4000,
        title: "The Lord of the Rings",
        author: "J.R.R. Tolkien",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
      )
    )
  }
}
