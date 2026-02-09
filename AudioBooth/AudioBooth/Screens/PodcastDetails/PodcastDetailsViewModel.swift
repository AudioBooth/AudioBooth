import API
import Combine
import Foundation
import Logging
import Models

final class PodcastDetailsViewModel: PodcastDetailsView.Model {
  private var podcastsService: PodcastsService { Audiobookshelf.shared.podcasts }
  private let playerManager = PlayerManager.shared
  private var apiEpisodes: [PodcastEpisode] = []
  private var cancellables = Set<AnyCancellable>()

  init(podcastID: String) {
    super.init(podcastID: podcastID)
    observePlayer()
  }

  override func onAppear() {
    Task {
      await loadPodcast()
    }
  }

  override func onPlayEpisode(_ episode: Episode) {
    guard let apiEpisode = apiEpisodes.first(where: { $0.id == episode.id }) else { return }

    if playerManager.current?.id == episode.id {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.onTogglePlaybackTapped()
      }
    } else {
      playerManager.setCurrent(
        episode: apiEpisode,
        podcastID: podcastID,
        podcastTitle: title,
        podcastAuthor: author,
        coverURL: coverURL
      )
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
      description: old.description,
      isCompleted: progress >= 1.0,
      progress: progress,
      chapters: old.chapters
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

        return Episode(
          id: apiEpisode.id,
          title: apiEpisode.title,
          season: apiEpisode.season,
          episode: apiEpisode.episode,
          publishedAt: publishedAt,
          duration: apiEpisode.duration,
          description: apiEpisode.description,
          isCompleted: progress >= 1.0,
          progress: progress,
          chapters: chapters
        )
      }

      error = nil
      isLoading = false
    } catch {
      isLoading = false
      self.error = "Failed to load podcast details. Please check your connection and try again."
      AppLogger.viewModel.error("Failed to load podcast: \(error)")
    }
  }
}
