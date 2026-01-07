import API
import AVKit
import Combine
import SwiftData
import SwiftUI

struct BookPlayer: View {
  @Binding var model: Model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @ObservedObject private var playerManager = PlayerManager.shared
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient(
          gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.3)]),
          startPoint: .top,
          endPoint: .bottom
        )
        .ignoresSafeArea()

        Group {
          if verticalSizeClass == .compact {
            landscapeLayout
          } else {
            portraitLayout
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(
            "Minify",
            systemImage: "chevron.down",
            action: {
              playerManager.hideFullPlayer()
              dismiss()
            }
          )
          .tint(.primary)
        }

        ToolbarItem(placement: .topBarTrailing) {
          AirPlayButton()
            .frame(width: 44, height: 44)
            .tint(.primary)
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .series, .author, .narrator, .genre, .tag, .offline:
          LibraryPage(model: LibraryPageModel(destination: destination))
        case .playlist, .collection:
          EmptyView()
        }
      }
    }
    .preferredColorScheme(.dark)
    .sheet(
      isPresented: Binding(
        get: { model.chapters?.isPresented ?? false },
        set: { newValue in model.chapters?.isPresented = newValue }
      )
    ) {
      if let chapters = model.chapters {
        ChapterPickerSheet(model: chapters)
      }
    }
    .sheet(isPresented: $model.speed.isPresented) {
      SpeedPickerSheet(model: $model.speed)
    }
    .sheet(isPresented: $model.timer.isPresented) {
      TimerPickerSheet(model: $model.timer)
    }
    .sheet(item: $model.timer.completedAlert) { model in
      TimerCompletedAlertView(model: model)
    }
    .sheet(
      isPresented: Binding(
        get: { model.bookmarks?.isPresented ?? false },
        set: { newValue in model.bookmarks?.isPresented = newValue }
      )
    ) {
      if let bookmarks = model.bookmarks {
        BookmarkViewerSheet(model: bookmarks)
      }
    }
    .sheet(
      isPresented: Binding(
        get: { model.history?.isPresented ?? false },
        set: { newValue in model.history?.isPresented = newValue }
      )
    ) {
      if let history = model.history {
        PlaybackHistorySheet(model: history)
      }
    }
  }

  private var portraitLayout: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        cover

        Spacer(minLength: 24)

        VStack(spacing: 32) {
          chaptersDisplay

          PlaybackProgressView(model: $model.playbackProgress)

          mainPlaybackControls
        }

        Spacer(minLength: 24)

        bottomControlBar
      }
      .padding(.horizontal, 24)
      .disabled(model.isLoading)
    }
  }

  private var landscapeLayout: some View {
    HStack(spacing: 24) {
      cover
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }

      VStack(spacing: 24) {
        Spacer()

        chaptersDisplay

        PlaybackProgressView(model: $model.playbackProgress)

        mainPlaybackControls

        bottomControlBar

        Spacer()
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 24)
      .disabled(model.isLoading)
    }
    .padding(.horizontal, 24)
  }

  private var cover: some View {
    NavigationLink(value: NavigationDestination.book(id: model.id)) {
      CoverImage(url: model.coverURL)
        .frame(minWidth: 200, maxWidth: 400, minHeight: 200, maxHeight: 400)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
    .accessibilityLabel("Book details")
    .overlay(alignment: .topLeading) {
      timerOverlay
    }
    .padding(.horizontal, 30)
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var timerOverlay: some View {
    switch model.timer.current {
    case .preset(let seconds), .custom(let seconds):
      let text = Duration.seconds(seconds).formatted(
        .units(
          allowed: [.hours, .minutes, .seconds],
          width: .narrow
        )
      )
      let remaining = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds]))
      let accessibilityLabel = "Sleep timer: \(remaining) remaining"
      timerBadge(text: Text(text), accessibilityLabel: accessibilityLabel)
    case .chapters(let count):
      let label = count > 1 ? "End of \(count) chapters" : "End of chapter"
      let accessibilityLabel = "Sleep timer: \(label)"
      timerBadge(text: Text(label), accessibilityLabel: accessibilityLabel)
    case .none:
      EmptyView()
    }
  }

  @ViewBuilder
  private func timerBadge(text: Text, accessibilityLabel: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "timer")
      text
    }
    .font(.footnote)
    .fontWeight(.bold)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.black.opacity(0.7))
    .foregroundColor(.white)
    .clipShape(Capsule())
    .padding(4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var chaptersDisplay: some View {
    if let chapters = model.chapters,
      let chapter = chapters.current
    {
      Button(action: { chapters.isPresented = true }) {
        HStack {
          if chapters.chapters.count > 1 {
            Image(systemName: "list.bullet")
              .foregroundColor(.white.opacity(0.7))
          }

          Text(chapter.title)
            .foregroundColor(.white)
            .font(.headline)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      }
      .allowsHitTesting(chapters.chapters.count > 1)
      .padding(.horizontal, 8)
    } else {
      Text(model.title)
        .foregroundColor(.white)
        .font(.headline)
        .lineLimit(1)
    }
  }

  private var mainPlaybackControls: some View {
    HStack(spacing: 0) {
      if let chapters = model.chapters {
        let isFirstChapter = chapters.currentIndex == 0
        Button(action: { chapters.onPreviousChapterTapped() }) {
          Image(systemName: "backward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || isFirstChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(isFirstChapter)
        .accessibilityLabel("Previous chapter")

        Spacer(minLength: 16)
      }

      Button(action: { model.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval) }) {
        Image(
          systemName: "\(Int(preferences.skipBackwardInterval)).arrow.trianglehead.counterclockwise"
        )
        .font(.system(size: 36, weight: .thin))
        .minimumScaleFactor(0.5)
        .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")

      Spacer(minLength: 16)

      Button(action: model.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(model.isLoading ? Color.white.opacity(0.3) : Color.white)

          if model.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .black))
              .scaleEffect(0.8)
          } else {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 32))
              .foregroundColor(.black)
              .offset(x: model.isPlaying ? 0 : 3)
          }
        }
        .frame(minWidth: 60, maxWidth: 80, minHeight: 60, maxHeight: 80)
      }
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

      Spacer(minLength: 16)

      Button(action: { model.onSkipForwardTapped(seconds: preferences.skipForwardInterval) }) {
        Image(systemName: "\(Int(preferences.skipForwardInterval)).arrow.trianglehead.clockwise")
          .font(.system(size: 36, weight: .thin))
          .minimumScaleFactor(0.5)
          .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")

      if let chapters = model.chapters {
        Spacer(minLength: 16)

        let isLastChapter = chapters.currentIndex == chapters.chapters.count - 1
        Button(action: { chapters.onNextChapterTapped() }) {
          Image(systemName: "forward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || isLastChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(isLastChapter)
        .accessibilityLabel("Next chapter")
      }
    }
  }

  private var bottomControlBar: some View {
    HStack(alignment: .bottom, spacing: 0) {
      Button(action: { model.speed.isPresented = true }) {
        VStack(spacing: 6) {
          Text("\(String(format: "%.1f", model.speed.playbackSpeed))×")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(height: 20)
          Text("Speed")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
        }
      }
      .frame(maxWidth: .infinity)

      Button(action: { model.timer.isPresented = true }) {
        VStack(spacing: 6) {
          Image(systemName: "timer")
            .font(.system(size: 20))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
          Text("Timer")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
        }
      }
      .frame(maxWidth: .infinity)

      if model.bookmarks != nil {
        Button(action: { model.onBookmarksTapped() }) {
          VStack(spacing: 6) {
            Image(systemName: "bookmark")
              .font(.system(size: 20))
              .foregroundColor(.white)
              .frame(width: 20, height: 20)
            Text("Bookmarks")
              .font(.caption2)
              .foregroundColor(.white.opacity(0.7))
          }
        }
        .frame(maxWidth: .infinity)
      }

      if model.history != nil {
        Button(action: { model.onHistoryTapped() }) {
          VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
              .font(.system(size: 20))
              .foregroundColor(.white)
              .frame(width: 20, height: 20)
            Text("History")
              .font(.caption2)
              .foregroundColor(.white.opacity(0.7))
          }
        }
        .frame(maxWidth: .infinity)
      }

      if Audiobookshelf.shared.authentication.permissions?.download == true {
        Button(action: { model.onDownloadTapped() }) {
          VStack(spacing: 6) {
            Image(systemName: downloadIcon)
              .font(.system(size: 20))
              .foregroundColor(.white)
              .frame(width: 20, height: 20)
              .opacity([.downloaded, .notDownloaded].contains(model.downloadState) ? 1 : 0)
              .overlay {
                if case .downloading(let progress) = model.downloadState {
                  ProgressView(value: progress)
                    .progressViewStyle(GaugeProgressViewStyle(tint: .white))
                }
              }
            Text(downloadText)
              .font(.caption2)
              .lineLimit(1)
              .hidden()
              .overlay(alignment: .top) {
                Text(downloadText)
                  .font(.caption2)
                  .foregroundColor(.white.opacity(0.7))
                  .fixedSize(horizontal: false, vertical: true)
              }
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 12)
  }

  private var downloadIcon: String {
    switch model.downloadState {
    case .downloading:
      return "stop.circle"
    case .downloaded:
      return "internaldrive"
    case .notDownloaded:
      return "icloud.and.arrow.down"
    }
  }

  private var downloadText: String {
    switch model.downloadState {
    case .downloading:
      return "Cancel"
    case .downloaded:
      return "Remove"
    case .notDownloaded:
      return "Download"
    }
  }
}

extension BookPlayer {
  @Observable
  class Model: ObservableObject {
    let id: String
    let title: String
    let author: String?
    let coverURL: URL?

    var isPlaying: Bool
    var isLoading: Bool
    var speed: SpeedPickerSheet.Model
    var timer: TimerPickerSheet.Model
    var chapters: ChapterPickerSheet.Model?
    var bookmarks: BookmarkViewerSheet.Model?
    var history: PlaybackHistorySheet.Model?
    var playbackProgress: PlaybackProgressView.Model

    var downloadState: DownloadManager.DownloadState

    var isPresented: Bool = true

    func onTogglePlaybackTapped() {}
    func onPauseTapped() {}
    func onPlayTapped() {}
    func onSkipForwardTapped(seconds: Double) {}
    func onSkipBackwardTapped(seconds: Double) {}
    func onProgressChanged(to progress: Double) {}
    func onDownloadTapped() {}
    func onBookmarksTapped() {}
    func onHistoryTapped() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      author: String?,
      coverURL: URL?,
      isPlaying: Bool = false,
      isLoading: Bool = false,
      speed: SpeedPickerSheet.Model,
      timer: TimerPickerSheet.Model,
      chapters: ChapterPickerSheet.Model? = nil,
      bookmarks: BookmarkViewerSheet.Model? = nil,
      history: PlaybackHistorySheet.Model? = nil,
      playbackProgress: PlaybackProgressView.Model,
      downloadState: DownloadManager.DownloadState = .notDownloaded
    ) {
      self.id = id
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.isPlaying = isPlaying
      self.isLoading = isLoading
      self.speed = speed
      self.timer = timer
      self.chapters = chapters
      self.bookmarks = bookmarks
      self.history = history
      self.playbackProgress = playbackProgress
      self.downloadState = downloadState
    }
  }
}

extension BookPlayer.Model {
  static var mock: BookPlayer.Model {
    let model = BookPlayer.Model(
      title: "Sample Audiobook",
      author: "Sample Author",
      coverURL: nil,
      speed: .mock,
      timer: .mock,
      chapters: .mock,
      playbackProgress: .mock
    )
    return model
  }
}

struct AirPlayButton: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let routePickerView = AVRoutePickerView()
    routePickerView.backgroundColor = UIColor.clear
    routePickerView.tintColor = UIColor.white
    return routePickerView
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

#Preview {
  BookPlayer(model: .constant(.mock))
}
