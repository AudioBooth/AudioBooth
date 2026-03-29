import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayPodcastDetails {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private let podcast: Podcast
  private var loadingCancellable: Task<Void, Never>?

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying, podcast: Podcast) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying
    self.podcast = podcast

    template = CPListTemplate(title: podcast.title, sections: [])
    template.emptyViewTitleVariants = [String(localized: "Loading Episodes...")]

    Task { await loadEpisodes() }
  }

  private func loadEpisodes() async {
    do {
      let fullPodcast = try await Audiobookshelf.shared.podcasts.fetch(id: podcast.id)
      let episodes = fullPodcast.media.episodes ?? []

      let sortedEpisodes = episodes.sorted { a, b in
        (a.publishedAt ?? 0) > (b.publishedAt ?? 0)
      }

      let items = sortedEpisodes.map { episode in
        createListItem(for: episode)
      }

      if items.isEmpty {
        template.emptyViewTitleVariants = [String(localized: "No Episodes")]
      }

      let section = CPListSection(items: items)
      template.updateSections([section])
    } catch {
      template.emptyViewTitleVariants = [String(localized: "Failed to Load Episodes")]
      template.updateSections([])
    }
  }

  private func createListItem(for episode: PodcastEpisode) -> CPListItem {
    var detailText: String?
    if let publishedAt = episode.publishedAt {
      let date = Date(timeIntervalSince1970: TimeInterval(publishedAt) / 1000)
      detailText = date.formatted(date: .abbreviated, time: .omitted)
    }

    let item = CPListItem(
      text: episode.title,
      detailText: detailText
    )

    item.isPlaying = episode.id == PlayerManager.shared.current?.id

    if let coverURL = podcast.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onEpisodeSelected(episode, completion: completion)
    }

    return item
  }

  private func onEpisodeSelected(_ episode: PodcastEpisode, completion: @escaping () -> Void) {
    loadingCancellable = Task {
      PlayerManager.shared.setCurrent(
        episode: episode,
        podcastID: podcast.id,
        podcastTitle: podcast.title,
        podcastAuthor: podcast.author,
        coverURL: podcast.coverURL()
      )

      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))

      PlayerManager.shared.play()
      nowPlaying?.showNowPlaying()
      completion()
      loadingCancellable = nil
    }
  }

  private func waitForPlayerReady() async {
    guard PlayerManager.shared.current?.isLoading == true else { return }

    await withCheckedContinuation { continuation in
      observePlayerLoading(continuation: continuation)
    }
  }

  private func observePlayerLoading(continuation: CheckedContinuation<Void, Never>) {
    withObservationTracking {
      _ = PlayerManager.shared.current?.isLoading
    } onChange: {
      RunLoop.main.perform {
        if PlayerManager.shared.current?.isLoading == false {
          continuation.resume()
        } else {
          self.observePlayerLoading(continuation: continuation)
        }
      }
    }
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}
