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
            .tint(.red)
          }
        }
      }

      if !model.actions.isEmpty {
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

      if model.actions.contains(.removeFromContinueListening) {
        Button(action: model.onRemoveFromContinueListeningTapped) {
          Label("Remove from continue listening", systemImage: "eye.slash")
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
    struct Actions: OptionSet {
      let rawValue: Int

      static let markAsFinished = Actions(rawValue: 1 << 0)
      static let resetProgress = Actions(rawValue: 1 << 1)
      static let removeFromContinueListening = Actions(rawValue: 1 << 2)
      static let addToQueue = Actions(rawValue: 1 << 3)
      static let removeFromQueue = Actions(rawValue: 1 << 4)
    }

    var downloadState: DownloadManager.DownloadState
    var actions: Actions
    let authorInfo: BookCard.Author?
    let narratorInfo: BookCard.Narrator?
    let seriesInfo: BookCard.Series?

    func onAppear() {}
    func onDownloadTapped() {}
    func onCancelDownloadTapped() {}
    func onRemoveDownloadTapped() {}
    func onPlayTapped() {}
    func onAddToQueueTapped() {}
    func onRemoveFromQueueTapped() {}
    func onMarkAsFinishedTapped() {}
    func onResetProgressTapped() {}
    func onRemoveFromContinueListeningTapped() {}

    init(
      downloadState: DownloadManager.DownloadState = .notDownloaded,
      actions: Actions = [],
      authorInfo: BookCard.Author? = nil,
      narratorInfo: BookCard.Narrator? = nil,
      seriesInfo: BookCard.Series? = nil
    ) {
      self.downloadState = downloadState
      self.actions = actions
      self.authorInfo = authorInfo
      self.narratorInfo = narratorInfo
      self.seriesInfo = seriesInfo
    }
  }
}
