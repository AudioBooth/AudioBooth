import Combine
import SwiftUI

struct PlayerOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss

  @AppStorage("marqueeLoopMode") private var marqueeLoopMode: MarqueeLoopMode = .playOnce

  @ObservedObject var model: Model

  var body: some View {
    List {
      if model.hasChapters {
        Button(action: {
          model.onChaptersTapped()
          dismiss()
        }) {
          Label("Chapters", systemImage: "list.bullet")
        }
      }

      Button(action: {
        model.onSpeedTapped()
        dismiss()
      }) {
        Label(
          "Speed (\(model.speed.formatted(.number.precision(.fractionLength(0...2))))×)",
          systemImage: "gauge.with.dots.needle.33percent"
        )
      }

      Button(action: {
        model.onDownloadTapped()
        dismiss()
      }) {
        switch model.downloadState {
        case .downloading:
          Label("Cancel Download", systemImage: "stop.circle")
        case .paused:
          Label("Resume Download", systemImage: "arrow.clockwise.icloud")
        case .downloaded:
          Label("Remove from Watch", systemImage: "trash")
        case .notDownloaded:
          Label("Download to Watch", systemImage: "icloud.and.arrow.down")
        }
      }

      if case .paused = model.downloadState {
        Button(action: {
          model.onRemoveDownloadTapped()
          dismiss()
        }) {
          Label("Remove from Watch", systemImage: "trash")
        }
      }

      Picker(
        selection: $marqueeLoopMode,
        content: {
          ForEach(MarqueeLoopMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        },
        label: {
          Label("Title Scrolling", systemImage: "text.append")
        }
      )
    }
    .navigationTitle("Options")
    .navigationBarTitleDisplayMode(.inline)
  }
}

extension PlayerOptionsSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    var isPresented: Bool = false
    var isHidden: Bool
    var hasChapters: Bool
    var downloadState: DownloadManager.DownloadState
    var speed: Float
    var speedPicker: SpeedPickerSheet.Model

    var isCoverDownloadEnabled: Bool {
      switch downloadState {
      case .notDownloaded, .paused: true
      case .downloading, .downloaded: false
      }
    }

    init(
      isHidden: Bool = false,
      hasChapters: Bool = false,
      downloadState: DownloadManager.DownloadState = .notDownloaded,
      speed: Float = 1.0
    ) {
      self.isHidden = isHidden
      self.hasChapters = hasChapters
      self.downloadState = downloadState
      self.speed = speed
      self.speedPicker = SpeedPickerSheet.Model(speed: speed)
    }

    func onChaptersTapped() {}
    func onDownloadTapped() {}
    func onRemoveDownloadTapped() {}
    func onSpeedTapped() {
      speedPicker.isPresented = true
    }
  }
}

#Preview {
  NavigationStack {
    PlayerOptionsSheet(
      model: PlayerOptionsSheet.Model(
        hasChapters: true,
        downloadState: .notDownloaded,
        speed: 1.5
      )
    )
  }
}
