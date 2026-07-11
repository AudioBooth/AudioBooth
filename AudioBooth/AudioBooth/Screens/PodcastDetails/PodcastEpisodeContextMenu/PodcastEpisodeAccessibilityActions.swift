import API
import Combine
import SwiftUI

struct PodcastEpisodeAccessibilityActions: ViewModifier {
  let episodeID: String
  let menu: PodcastEpisodeContextMenu.Model?

  @ObservedObject private var playerManager = PlayerManager.shared
  @ObservedObject private var downloadManager = DownloadManager.shared

  private let audiobookshelf = Audiobookshelf.shared

  func body(content: Content) -> some View {
    if let menu {
      content.accessibilityActions {
        actions(for: menu)
      }
    } else {
      content
    }
  }

  private var isPlayingThisEpisode: Bool {
    playerManager.current?.id == episodeID && playerManager.isPlaying
  }

  private var downloadState: DownloadManager.DownloadState {
    downloadManager.downloadStates[episodeID] ?? .notDownloaded
  }

  @ViewBuilder
  private func actions(for menu: PodcastEpisodeContextMenu.Model) -> some View {
    if isPlayingThisEpisode {
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

    if menu.actions.contains(.addToPlaylist) {
      Button("Add to Playlist", action: menu.onAddToPlaylistTapped)
    }
  }
}

extension View {
  func podcastEpisodeAccessibilityActions(
    episodeID: String,
    menu: PodcastEpisodeContextMenu.Model?
  ) -> some View {
    modifier(PodcastEpisodeAccessibilityActions(episodeID: episodeID, menu: menu))
  }
}
