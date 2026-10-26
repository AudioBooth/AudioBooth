import API
import Foundation
import OSLog

final class PodcastEpisodesViewModel: SectionDetailView.Model {
  private let connectivityManager = WatchConnectivityManager.shared

  init(podcast: WatchPodcast) {
    super.init(sectionID: podcast.id, title: podcast.title)
  }

  override func onLoad() async {
    guard rows.isEmpty else { return }

    state = .loading

    let podcast: Podcast
    do {
      podcast = try await Audiobookshelf.shared.podcasts.fetch(id: id)
    } catch {
      AppLogger.watchConnectivity.error("Failed to load podcast \(self.id): \(error)")
      state = .error(String(localized: "Failed to load episodes."))
      return
    }

    let coverURL = podcast.coverURL()?.appending(queryItems: [URLQueryItem(name: "width", value: "200")])
    let progress = connectivityManager.progress
    let episodes = (podcast.media.episodes ?? []).sorted { ($0.publishedAt ?? 0) > ($1.publishedAt ?? 0) }

    rows = episodes.map { episode in
      ContinueListeningRowModel(
        book: WatchBook(
          id: episode.id,
          podcastID: podcast.id,
          title: episode.title,
          authorName: podcast.title,
          coverURL: coverURL,
          duration: episode.duration ?? 0,
          chapters: [],
          currentTime: progress[episode.id, default: 0]
        )
      )
    }
    state = .loaded
  }
}
