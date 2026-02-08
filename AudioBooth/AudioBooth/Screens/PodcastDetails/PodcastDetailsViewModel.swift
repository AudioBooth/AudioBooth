import API
import Foundation
import Logging

final class PodcastDetailsViewModel: PodcastDetailsView.Model {
  private var podcastsService: PodcastsService { Audiobookshelf.shared.podcasts }

  init(podcastID: String) {
    super.init(podcastID: podcastID)
  }

  override func onAppear() {
    Task {
      await loadPodcast()
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

      let apiEpisodes = podcast.media.episodes ?? []

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

        return Episode(
          id: apiEpisode.id,
          title: apiEpisode.title,
          season: apiEpisode.season,
          episode: apiEpisode.episode,
          publishedAt: publishedAt,
          duration: apiEpisode.duration,
          description: apiEpisode.description,
          isCompleted: false,
          isInProgress: false,
          progress: 0,
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
