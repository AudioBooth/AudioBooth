import API
import Combine
import SwiftUI

struct PodcastEpisodeContextMenu: View {
  private let audiobookshelf = Audiobookshelf.shared

  @ObservedObject var model: Model

  var body: some View {
    Group {
      ControlGroup {
        Button(action: model.onPlayTapped) {
          Label("Play", systemImage: "play.fill")
        }

        if model.actions.contains(.addToQueue) {
          Button(action: model.onAddToQueueTapped) {
            Label("Add to Queue", systemImage: "text.badge.plus")
          }
        } else if model.actions.contains(.removeFromQueue) {
          Button(action: model.onRemoveFromQueueTapped) {
            Label("Remove from Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
          }
        }

        if audiobookshelf.authentication.permissions?.download == true {
          switch model.downloadState {
          case .notDownloaded:
            Button(action: model.onDownloadTapped) {
              Label("Download", systemImage: "arrow.down.circle")
            }
          case .downloading:
            Button(action: model.onCancelDownloadTapped) {
              Label("Cancel Download", systemImage: "stop.circle")
            }
          case .downloaded:
            Button(role: .destructive, action: model.onRemoveDownloadTapped) {
              Label("Remove Download", systemImage: "trash")
            }
          }
        }
      }

      if model.actions.contains(.markAsFinished) || model.actions.contains(.resetProgress)
        || model.actions.contains(.addToPlaylist)
      {
        Divider()
      }

      if model.actions.contains(.markAsFinished) {
        Button(action: model.onMarkAsFinishedTapped) {
          Label("Mark as Finished", systemImage: "checkmark.shield")
        }
      }

      if model.actions.contains(.resetProgress) {
        Button(action: model.onResetProgressTapped) {
          Label("Reset Progress", systemImage: "arrow.counterclockwise")
        }
      }

      if model.actions.contains(.addToPlaylist) {
        Button(action: model.onAddToPlaylistTapped) {
          Label("Add to Playlist", systemImage: "text.badge.plus")
        }
      }
    }
    .onAppear(perform: model.onAppear)
  }
}

extension PodcastEpisodeContextMenu {
  @Observable
  class Model: ObservableObject {
    struct Actions: OptionSet {
      let rawValue: Int

      static let markAsFinished = Actions(rawValue: 1 << 0)
      static let resetProgress = Actions(rawValue: 1 << 1)
      static let addToQueue = Actions(rawValue: 1 << 2)
      static let removeFromQueue = Actions(rawValue: 1 << 3)
      static let addToPlaylist = Actions(rawValue: 1 << 4)
    }

    var downloadState: DownloadManager.DownloadState
    var actions: Actions
    var showingPlaylistSheet = false

    func onAppear() {}
    func onPlayTapped() {}
    func onAddToQueueTapped() {}
    func onRemoveFromQueueTapped() {}
    func onDownloadTapped() {}
    func onCancelDownloadTapped() {}
    func onRemoveDownloadTapped() {}
    func onMarkAsFinishedTapped() {}
    func onResetProgressTapped() {}
    func onAddToPlaylistTapped() {}

    init(
      downloadState: DownloadManager.DownloadState = .notDownloaded,
      actions: Actions = []
    ) {
      self.downloadState = downloadState
      self.actions = actions
    }
  }
}
