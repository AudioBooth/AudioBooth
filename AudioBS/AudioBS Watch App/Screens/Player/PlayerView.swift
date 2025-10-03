import Combine
import NukeUI
import SwiftUI

struct PlayerView: View {
  @Environment(\.dismiss) private var dismiss

  private var playerManager: PlayerManager { .shared }

  @StateObject var model: Model

  var body: some View {
    VStack(spacing: 6) {
      Button(action: {
        if model.downloadState != .downloaded {
          model.onDownloadTapped()
        }
      }) {
        Cover(
          url: model.coverURL,
          state: model.downloadState
        )
      }
      .buttonStyle(.plain)
      .allowsHitTesting(model.downloadState == .notDownloaded)

      content

      Playback(
        current: model.current,
        remaining: model.remaining,
        totalTimeRemaining: model.totalTimeRemaining
      )
      .padding(.bottom, 12)
    }
    .padding(.top, -16)
    .toolbar {
      toolbar
    }
    .sheet(isPresented: $model.options.isPresented) {
      PlayerOptionsSheet(model: $model.options)
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
      VolumeView()
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
    }

    ToolbarItem(placement: .topBarTrailing) {
      Button(
        action: {
          model.options.isPresented = true
        },
        label: {
          Image(systemName: "ellipsis")
        }
      )
    }

    ToolbarItemGroup(placement: .bottomBar) {
      Button(
        action: model.skipBackward,
        label: {
          Image(systemName: "gobackward.30")
        }
      )

      Button(
        action: model.togglePlayback,
        label: {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
        }
      )
      .overlay { progress }
      .controlSize(.large)

      Button(
        action: model.skipForward,
        label: {
          Image(systemName: "goforward.30")
        }
      )
    }

  }

  var progress: some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.5), lineWidth: 1)

      Circle()
        .trim(from: 0, to: model.progress)
        .stroke(
          Color.white,
          style: StrokeStyle(lineWidth: 1, lineCap: .round)
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

        if !model.author.isEmpty {
          Text("by \(model.author)")
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
  @Observable
  class Model: ObservableObject, Identifiable {
    var isLoading: Bool = false

    var isPlaying: Bool
    var progress: Double
    var current: Double
    var remaining: Double
    var totalTimeRemaining: Double

    var title: String
    var author: String
    var coverURL: URL?
    var chapters: ChapterPickerSheet.Model?
    var downloadState: DownloadManager.DownloadState
    var options: PlayerOptionsSheet.Model

    func togglePlayback() {}
    func skipBackward() {}
    func skipForward() {}
    func onDownloadTapped() {}

    init(
      isPlaying: Bool = false,
      progress: Double = 0,
      current: Double = 0,
      remaining: Double = 0,
      totalTimeRemaining: Double = 0,
      title: String = "",
      author: String = "",
      coverURL: URL? = nil,
      chapters: ChapterPickerSheet.Model? = nil,
      downloadState: DownloadManager.DownloadState = .notDownloaded
    ) {
      self.isPlaying = isPlaying
      self.progress = progress
      self.current = current
      self.remaining = remaining
      self.totalTimeRemaining = totalTimeRemaining
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.chapters = chapters
      self.downloadState = downloadState
      self.options = PlayerOptionsSheet.Model(
        hasChapters: chapters != nil,
        downloadState: downloadState
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
