import API
import Combine
import Logging
import Models
import SwiftUI

final class PodcastEpisodeDetailViewModel: PodcastEpisodeDetailView.Model {
  private let podcastID: String
  private let podcastTitle: String
  private let podcastAuthor: String?
  private let coverURL: URL?
  private let episodeID: String
  private let episodeSize: Int64?
  private let apiEpisode: PodcastEpisode?

  private let playerManager = PlayerManager.shared
  private let downloadManager = DownloadManager.shared
  private var cancellables = Set<AnyCancellable>()

  init(
    podcastID: String,
    podcastTitle: String,
    podcastAuthor: String?,
    coverURL: URL?,
    episode: PodcastDetailsView.Model.Episode
  ) {
    self.podcastID = podcastID
    self.podcastTitle = podcastTitle
    self.podcastAuthor = podcastAuthor
    self.coverURL = coverURL
    self.episodeID = episode.id
    self.episodeSize = episode.size
    self.apiEpisode = episode.apiEpisode

    super.init(episode: episode)

    observePlayer()
    observeDownloadState()
  }

  override func onPlay() {
    if playerManager.current?.id == episodeID {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.onTogglePlaybackTapped()
      }
      return
    }

    if let localEpisode = try? LocalEpisode.fetch(episodeID: episodeID) {
      playerManager.setCurrent(localEpisode)
    } else if let apiEpisode {
      playerManager.setCurrent(
        episode: apiEpisode,
        podcastID: podcastID,
        podcastTitle: podcastTitle,
        podcastAuthor: podcastAuthor,
        coverURL: coverURL
      )
    }
    playerManager.play()
  }

  override func onToggleFinished() {
    let episodeProgressID = "\(podcastID)/\(episodeID)"
    Task {
      do {
        if isCompleted {
          let progress = try MediaProgress.fetch(bookID: episodeID)
          let progressID: String
          if let progress, let id = progress.id {
            progressID = id
          } else {
            let apiProgress = try await Audiobookshelf.shared.libraries.fetchMediaProgress(
              bookID: episodeProgressID
            )
            progressID = apiProgress.id
          }
          try await Audiobookshelf.shared.libraries.resetBookProgress(progressID: progressID)
          if let progress {
            try progress.delete()
          }
          isCompleted = false
          self.progress = 0
        } else {
          try MediaProgress.markAsFinished(for: episodeID)
          try await Audiobookshelf.shared.libraries.markAsFinished(bookID: episodeProgressID)
          isCompleted = true
          self.progress = 1.0
        }
      } catch {
        AppLogger.viewModel.error("Failed to toggle episode finished: \(error)")
      }
    }
  }

  override func onDownload() {
    switch downloadState {
    case .notDownloaded:
      let size = episodeSize ?? 0
      var details = ""
      if let duration, duration > 0 {
        details = Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
      }
      if size > 0 {
        if !details.isEmpty { details += " • " }
        details += size.formatted(.byteCount(style: .file))
      }
      Task {
        let canDownload = await StorageManager.shared.canDownload(additionalBytes: size)
        guard canDownload else {
          Toast(error: "Storage limit reached").show()
          return
        }
        downloadManager.startDownload(
          for: episodeID,
          type: .episode(podcastID: podcastID, episodeID: episodeID),
          info: .init(
            title: title,
            details: details.isEmpty ? nil : details,
            coverURL: coverURL,
            startedAt: Date()
          )
        )
      }
    case .downloading:
      downloadManager.cancelDownload(for: episodeID)
    case .downloaded:
      downloadManager.deleteEpisodeDownload(episodeID: episodeID, podcastID: podcastID)
    }
  }

  override func onAddToPlaylist() {
    playlistSheetModel = CollectionSelectorSheetModel(
      bookID: podcastID,
      episodeID: episodeID,
      mode: .playlists
    )
  }

  private func observePlayer() {
    playerManager.$current
      .sink { [weak self] current in
        guard let self else { return }
        observeIsPlaying(current)
      }
      .store(in: &cancellables)
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.podcastID == podcastID, current.id == episodeID else {
      isPlaying = false
      return
    }

    isPlaying = current.isPlaying

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updatePlayingState()
        self.observeIsPlaying(self.playerManager.current)
      }
    }
  }

  private func updatePlayingState() {
    let current = playerManager.current
    if current?.podcastID == podcastID, current?.id == episodeID {
      isPlaying = current?.isPlaying ?? false
    } else {
      isPlaying = false
    }
  }

  private func observeDownloadState() {
    downloadManager.$downloadStates
      .sink { [weak self] states in
        guard let self else { return }
        downloadState = states[episodeID] ?? .notDownloaded
      }
      .store(in: &cancellables)
  }
}
