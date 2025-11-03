import API
import AVKit
import Combine
import SwiftData
import SwiftUI

struct BookPlayer: View {
  @Binding var model: Model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @StateObject private var playerManager = PlayerManager.shared

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
      if let chapters = Binding($model.chapters) {
        ChapterPickerSheet(model: chapters)
      }
    }
    .sheet(isPresented: $model.speed.isPresented) {
      SpeedPickerSheet(model: $model.speed)
    }
    .sheet(isPresented: $model.timer.isPresented) {
      TimerPickerSheet(model: $model.timer)
    }
  }

  private var portraitLayout: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        cover

        Spacer()

        chaptersDisplay

        PlaybackProgressView(model: $model.playbackProgress)

        mainPlaybackControls

        bottomControlBar
      }
      .padding(.horizontal, 24)
    }
  }

  private var landscapeLayout: some View {
    HStack(spacing: 24) {
      cover
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

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
    }
    .padding(.horizontal, 24)
  }

  private var cover: some View {
    CoverImage(url: model.coverURL)
      .frame(maxWidth: 280, maxHeight: 280)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
      .padding(30)
      .overlay(alignment: .topLeading) {
        timerOverlay
      }
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
      timerBadge(text: Text(text))
    case .chapters(let count):
      timerBadge(text: Text(count > 1 ? "End of \(count) chapters" : "End of chapter"))
    case .none:
      EmptyView()
    }
  }

  @ViewBuilder
  private func timerBadge(text: Text) -> some View {
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
    .padding(.top, 40)
    .padding(.trailing, 40)
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
    HStack(spacing: 32) {
      if let chapters = model.chapters {
        let isFirstChapter = chapters.currentIndex == 0
        Button(action: { chapters.onPreviousChapterTapped() }) {
          Image(systemName: "backward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || isFirstChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(model.isLoading || isFirstChapter)
      }

      Button(action: { model.onSkipBackwardTapped(seconds: 30) }) {
        Image(systemName: "30.arrow.trianglehead.counterclockwise")
          .font(.system(size: 40, weight: .thin))
          .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .disabled(model.isLoading)

      Button(action: model.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(model.isLoading ? Color.white.opacity(0.3) : Color.white)
            .frame(width: 75, height: 75)

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
      }
      .disabled(model.isLoading)

      Button(action: { model.onSkipForwardTapped(seconds: 30) }) {
        Image(systemName: "30.arrow.trianglehead.clockwise")
          .font(.system(size: 40, weight: .thin))
          .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .disabled(model.isLoading)

      if let chapters = model.chapters {
        let isLastChapter = chapters.currentIndex == chapters.chapters.count - 1
        Button(action: { chapters.onNextChapterTapped() }) {
          Image(systemName: "forward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || isLastChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(model.isLoading || isLastChapter)
      }
    }
    .padding(.bottom, 30)
  }

  private var bottomControlBar: some View {
    HStack(alignment: .bottom, spacing: 0) {
      Button(action: { model.speed.isPresented = true }) {
        VStack(spacing: 6) {
          Text("\(String(format: "%.1f", model.speed.playbackSpeed))×")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
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
          Text("Timer")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
        }
      }
      .frame(maxWidth: .infinity)

      VStack(spacing: 6) {
        AirPlayButton()
          .frame(width: 20, height: 20)
        Text("AirPlay")
          .font(.caption2)
          .foregroundColor(.white.opacity(0.7))
      }
      .frame(maxWidth: .infinity)

      Button(action: { model.onDownloadTapped() }) {
        VStack(spacing: 6) {
          Image(systemName: downloadIcon)
            .font(.system(size: 16))
            .foregroundColor(.white)
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
      return "Remove from Device"
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
    var playbackProgress: PlaybackProgressView.Model

    var downloadState: DownloadManager.DownloadState

    var isPresented: Bool = true

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
      self.playbackProgress = playbackProgress
      self.downloadState = downloadState
    }

    func onTogglePlaybackTapped() {}
    func onSkipForwardTapped(seconds: Double) {}
    func onSkipBackwardTapped(seconds: Double) {}
    func onProgressChanged(to progress: Double) {}
    func onDownloadTapped() {}
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
