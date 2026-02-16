import API
import Combine
import Foundation
import Logging
import Models

final class PodcastDetailsViewModel: PodcastDetailsView.Model {
  private var podcastsService: PodcastsService { Audiobookshelf.shared.podcasts }
  private let playerManager = PlayerManager.shared
  private let downloadManager = DownloadManager.shared
  private var apiEpisodes: [PodcastEpisode] = []
  private var localPodcast: LocalPodcast?
  private var cancellables = Set<AnyCancellable>()
  private let episodeID: String?

  init(podcastID: String, episodeID: String? = nil) {
    self.episodeID = episodeID
    super.init(podcastID: podcastID)
    observePlayer()
    observeDownloadStates()
  }

  override func onAppear() {
    guard apiEpisodes.isEmpty else { return }
    Task {
      loadLocalPodcast()
      await loadPodcast()
    }
  }

  override func onPlayEpisode(_ episode: Episode) {
    if playerManager.current?.id == episode.id {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.onTogglePlaybackTapped()
      }
      return
    }

    if let apiEpisode = apiEpisodes.first(where: { $0.id == episode.id }) {
      playerManager.setCurrent(
        episode: apiEpisode,
        podcastID: podcastID,
        podcastTitle: title,
        podcastAuthor: author,
        coverURL: coverURL
      )
      playerManager.play()
    } else if let localEpisode = localPodcast?.episodes.first(where: { $0.episodeID == episode.id }) {
      playerManager.setCurrent(localEpisode)
      playerManager.play()
    }
  }

  override func onToggleEpisodeFinished(_ episode: Episode) {
    let episodeProgressID = "\(podcastID)/\(episode.id)"

    Task {
      do {
        if episode.isCompleted {
          let progress = try MediaProgress.fetch(bookID: episode.id)
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
        } else {
          try MediaProgress.markAsFinished(for: episode.id)
          try await Audiobookshelf.shared.libraries.markAsFinished(bookID: episodeProgressID)
        }
        updateEpisodeProgress(episode.id)
      } catch {
        AppLogger.viewModel.error("Failed to toggle episode finished: \(error)")
      }
    }
  }

  override func onDownloadEpisode(_ episode: Episode) {
    let episodeID = episode.id

    switch episode.downloadState {
    case .notDownloaded:
      let size = episode.size ?? 0
      var details = ""
      if let duration = episode.duration, duration > 0 {
        details = Duration.seconds(duration).formatted(
          .units(allowed: [.hours, .minutes], width: .narrow)
        )
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
            title: episode.title,
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

  private func observeDownloadStates() {
    downloadManager.$downloadStates
      .sink { [weak self] states in
        guard let self else { return }
        for index in episodes.indices {
          let epID = episodes[index].id
          let newState = states[epID] ?? .notDownloaded
          if episodes[index].downloadState != newState {
            episodes[index].downloadState = newState
          }
        }
      }
      .store(in: &cancellables)
  }

  private func updateEpisodeProgress(_ episodeID: String) {
    guard let index = episodes.firstIndex(where: { $0.id == episodeID }) else { return }
    let progress = MediaProgress.progress(for: episodeID)
    let old = episodes[index]
    episodes[index] = Episode(
      id: old.id,
      title: old.title,
      season: old.season,
      episode: old.episode,
      publishedAt: old.publishedAt,
      duration: old.duration,
      size: old.size,
      description: old.description,
      isCompleted: progress >= 1.0,
      progress: progress,
      chapters: old.chapters,
      downloadState: old.downloadState
    )
  }

  private func observePlayer() {
    playerManager.$current
      .sink { [weak self] newCurrent in
        guard let self else { return }
        observeIsPlaying(newCurrent)
      }
      .store(in: &cancellables)
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.podcastID == podcastID else {
      currentlyPlayingEpisodeID = nil
      isPlaying = false
      return
    }

    updatePlayingState()

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updatePlayingState()
        self.observeIsPlaying(playerManager.current)
      }
    }
  }

  private func updatePlayingState() {
    let current = playerManager.current
    if current?.podcastID == podcastID {
      currentlyPlayingEpisodeID = current?.id
      isPlaying = current?.isPlaying ?? false
    } else {
      currentlyPlayingEpisodeID = nil
      isPlaying = false
    }
  }

  private func loadLocalPodcast() {
    do {
      guard let podcast = try LocalPodcast.fetch(podcastID: podcastID) else { return }
      localPodcast = podcast

      title = podcast.title
      author = podcast.author
      coverURL = podcast.coverURL(raw: true)
      description = podcast.podcastDescription?.replacingOccurrences(of: "\n", with: "<br>")
      genres = podcast.genres
      language = podcast.language
      podcastType = podcast.podcastType

      let localEpisodes = podcast.episodes

      episodeCount = localEpisodes.count

      let totalDuration = localEpisodes.reduce(0.0) { $0 + $1.duration }
      if totalDuration > 0 {
        durationText = Duration.seconds(totalDuration).formatted(
          .units(allowed: [.hours, .minutes], width: .narrow)
        )
      }

      episodes = localEpisodes.map { localEpisode in
        let progress = MediaProgress.progress(for: localEpisode.episodeID)
        let downloadState = downloadManager.downloadStates[localEpisode.episodeID] ?? .notDownloaded

        let chapters = localEpisode.orderedChapters.map { chapter in
          Chapter(
            id: chapter.id,
            start: chapter.start,
            end: chapter.end,
            title: chapter.title
          )
        }

        return Episode(
          id: localEpisode.episodeID,
          title: localEpisode.title,
          season: localEpisode.season,
          episode: localEpisode.episode,
          publishedAt: localEpisode.publishedAt,
          duration: localEpisode.duration,
          size: nil,
          description: localEpisode.episodeDescription,
          isCompleted: progress >= 1.0,
          progress: progress,
          chapters: chapters,
          downloadState: downloadState
        )
      }

      isLoading = false
      scrollToEpisodeID = episodeID
    } catch {
      AppLogger.viewModel.error("Failed to load local podcast: \(error)")
    }
  }

  private func loadPodcast() async {
    do {
      let podcast = try await podcastsService.fetch(id: podcastID)

      title = podcast.title
      author = podcast.author
      coverURL = podcast.coverURL(raw: true)
      description = podcast.description?.replacingOccurrences(of: "\n", with: "<br>")
      genres = podcast.genres
      tags = podcast.tags
      isExplicit = podcast.media.metadata.explicit ?? false
      language = podcast.language
      podcastType = podcast.podcastType
      episodeCount = podcast.numEpisodes

      apiEpisodes = podcast.media.episodes ?? []

      let totalDuration = apiEpisodes.reduce(0.0) { $0 + ($1.duration ?? 0) }
      if totalDuration > 0 {
        durationText = Duration.seconds(totalDuration).formatted(
          .units(
            allowed: [.hours, .minutes],
            width: .narrow
          )
        )
      }

      episodes = apiEpisodes.map { apiEpisode in
        let publishedAt: Date?
        if let timestamp = apiEpisode.publishedAt {
          publishedAt = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        } else {
          publishedAt = nil
        }

        let chapters = (apiEpisode.chapters ?? []).map { apiChapter in
          Chapter(
            id: apiChapter.id,
            start: apiChapter.start,
            end: apiChapter.end,
            title: apiChapter.title
          )
        }

        let progress = MediaProgress.progress(for: apiEpisode.id)

        let downloadState = downloadManager.downloadStates[apiEpisode.id] ?? .notDownloaded

        return Episode(
          id: apiEpisode.id,
          title: apiEpisode.title,
          season: apiEpisode.season,
          episode: apiEpisode.episode,
          publishedAt: publishedAt,
          duration: apiEpisode.duration,
          size: apiEpisode.audioTrack?.metadata?.size ?? apiEpisode.size,
          description: apiEpisode.description,
          isCompleted: progress >= 1.0,
          progress: progress,
          chapters: chapters,
          downloadState: downloadState
        )
      }

      error = nil
      isLoading = false
      scrollToEpisodeID = episodeID
    } catch {
      if localPodcast == nil {
        isLoading = false
        self.error = "Failed to load podcast details. Please check your connection and try again."
      }
      AppLogger.viewModel.error("Failed to load podcast: \(error)")
    }
  }
}
