import Combine
import SwiftUI

struct PlayerOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss

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
        model.onDownloadTapped()
        dismiss()
      }) {
        switch model.downloadState {
        case .downloading:
          Label("Cancel Download", systemImage: "stop.circle")
        case .downloaded:
          Label("Remove from Watch", systemImage: "trash")
        case .notDownloaded:
          Label("Download to Watch", systemImage: "icloud.and.arrow.down")
        }
      }
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

    init(
      isHidden: Bool = false,
      hasChapters: Bool = false,
      downloadState: DownloadManager.DownloadState = .notDownloaded
    ) {
      self.isHidden = isHidden
      self.hasChapters = hasChapters
      self.downloadState = downloadState
    }

    func onChaptersTapped() {}
    func onDownloadTapped() {}
  }
}

#Preview {
  NavigationStack {
    PlayerOptionsSheet(
      model: PlayerOptionsSheet.Model(
        hasChapters: true,
        downloadState: .notDownloaded
      )
    )
  }
}
