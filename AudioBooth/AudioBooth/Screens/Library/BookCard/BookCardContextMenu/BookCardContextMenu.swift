import API
import Combine
import SwiftUI

struct BookCardContextMenu: View {
  private let audiobookshelf = Audiobookshelf.shared

  @ObservedObject var model: Model

  var body: some View {
    Group {
      ControlGroup {
        Button(action: model.onPlayTapped) {
          Label("Play", systemImage: "play.fill")
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

      if !model.isFinished || model.hasProgress {
        Divider()
      }

      if !model.isFinished {
        Button(action: model.onMarkAsFinishedTapped) {
          Label("Mark as Finished", systemImage: "checkmark.circle")
        }
      }

      if model.hasProgress {
        Button(action: model.onResetProgressTapped) {
          Label("Reset Progress", systemImage: "arrow.counterclockwise")
        }
      }

      if model.authorInfo != nil || model.narratorInfo != nil || model.seriesInfo != nil {
        Divider()
      }

      if let authorInfo = model.authorInfo {
        NavigationLink(
          value: NavigationDestination.author(id: authorInfo.id, name: authorInfo.name)
        ) {
          Button(
            action: {},
            label: {
              Label("View Author", systemImage: "person.circle")
              Text(authorInfo.name)
            }
          )
          .allowsHitTesting(false)
        }
      }

      if let narratorInfo = model.narratorInfo {
        NavigationLink(value: NavigationDestination.narrator(name: narratorInfo.name)) {
          Button(
            action: {},
            label: {
              Label("View Narrator", systemImage: "person.wave.2")
              Text(narratorInfo.name)
            }
          )
          .allowsHitTesting(false)
        }
      }

      if let seriesInfo = model.seriesInfo {
        NavigationLink(
          value: NavigationDestination.series(id: seriesInfo.id, name: seriesInfo.name)
        ) {
          Button(
            action: {},
            label: {
              Label("View Series", systemImage: "books.vertical")
              Text(seriesInfo.name)
            }
          )
          .allowsHitTesting(false)
        }
      }
    }
    .onAppear(perform: model.onAppear)
  }
}

extension BookCardContextMenu {
  @Observable
  class Model: ObservableObject {
    var downloadState: DownloadManager.DownloadState
    var hasProgress: Bool
    var isFinished: Bool
    let authorInfo: BookCard.Author?
    let narratorInfo: BookCard.Narrator?
    let seriesInfo: BookCard.Series?

    func onAppear() {}
    func onDownloadTapped() {}
    func onCancelDownloadTapped() {}
    func onRemoveDownloadTapped() {}
    func onPlayTapped() {}
    func onMarkAsFinishedTapped() {}
    func onResetProgressTapped() {}

    init(
      downloadState: DownloadManager.DownloadState = .notDownloaded,
      hasProgress: Bool = false,
      isFinished: Bool = false,
      authorInfo: BookCard.Author? = nil,
      narratorInfo: BookCard.Narrator? = nil,
      seriesInfo: BookCard.Series? = nil
    ) {
      self.downloadState = downloadState
      self.hasProgress = hasProgress
      self.isFinished = isFinished
      self.authorInfo = authorInfo
      self.narratorInfo = narratorInfo
      self.seriesInfo = seriesInfo
    }
  }
}
