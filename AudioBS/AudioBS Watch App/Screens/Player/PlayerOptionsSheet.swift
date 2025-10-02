import SwiftUI

struct PlayerOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss

  @Binding var model: Model

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
        if case .downloading = model.downloadState {
          Label("Cancel Download", systemImage: "stop.circle")
        } else if case .downloaded = model.downloadState {
          Label("Remove from Device", systemImage: "trash")
        } else {
          Label("Download", systemImage: "icloud.and.arrow.down")
        }
      }
    }
    .navigationTitle("Options")
    .navigationBarTitleDisplayMode(.inline)
  }
}

extension PlayerOptionsSheet {
  @Observable class Model: Identifiable {
    let id = UUID()

    var isPresented: Bool = false
    var hasChapters: Bool
    var downloadState: DownloadManager.DownloadState

    init(
      hasChapters: Bool = false,
      downloadState: DownloadManager.DownloadState = .notDownloaded
    ) {
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
      model: .constant(
        PlayerOptionsSheet.Model(
          hasChapters: true,
          downloadState: .notDownloaded
        )
      )
    )
  }
}
