import API
import Combine
import SwiftUI

struct BookCardAccessibilityActions: ViewModifier {
  @ObservedObject var model: BookCard.Model
  @ObservedObject private var playerManager = PlayerManager.shared
  @ObservedObject private var downloadManager = DownloadManager.shared

  private let audiobookshelf = Audiobookshelf.shared

  func body(content: Content) -> some View {
    if let menu = model.contextMenu {
      content.accessibilityActions {
        actions(for: menu)
      }
    } else {
      content
    }
  }

  private var isPlayingThisBook: Bool {
    playerManager.current?.id == model.id && playerManager.isPlaying
  }

  private var downloadState: DownloadManager.DownloadState {
    downloadManager.downloadStates[model.id] ?? .notDownloaded
  }

  @ViewBuilder
  private func actions(for menu: BookCardContextMenu.Model) -> some View {
    if isPlayingThisBook {
      Button("Pause", action: playerManager.pause)
    } else {
      Button("Play", action: menu.onPlayTapped)
    }

    if audiobookshelf.authentication.server?.permissions?.download == true {
      switch downloadState {
      case .notDownloaded:
        Button("Download", action: menu.onDownloadTapped)
      case .downloading:
        Button("Cancel Download", action: menu.onCancelDownloadTapped)
      case .downloaded:
        Button("Remove Download", action: menu.onRemoveDownloadTapped)
      }
    }

    if menu.actions.contains(.addToQueue) {
      Button("Add to Queue", action: menu.onAddToQueueTapped)
    } else if menu.actions.contains(.removeFromQueue) {
      Button("Remove from Queue", action: menu.onRemoveFromQueueTapped)
    }

    if menu.actions.contains(.markAsFinished) {
      Button("Mark as Finished", action: menu.onMarkAsFinishedTapped)
    }

    if menu.actions.contains(.removeFromContinueListening) {
      Button("Remove from continue listening", action: menu.onRemoveFromContinueListeningTapped)
    }
  }
}

extension View {
  func bookCardAccessibilityActions(model: BookCard.Model) -> some View {
    modifier(BookCardAccessibilityActions(model: model))
  }
}
