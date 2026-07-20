import Foundation

public final class PodcastsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil,
    sortBy: SortBy? = nil,
    ascending: Bool = true,
    filter: String? = nil
  ) async throws -> Page<Podcast> {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    guard let library = await audiobookshelf.libraries.current else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "No library selected. Please select a library first."
      )
    }

    var query: [String: String] = [
      "minified": "1",
      "include": "rssfeed,numEpisodesIncomplete,share",
    ]

    if let limit {
      query["limit"] = String(limit)
    }
    if let page {
      query["page"] = String(page)
    }
    if let sortBy {
      query["sort"] = sortBy.rawValue
    }
    if !ascending {
      query["desc"] = "1"
    }
    if let filter {
      query["filter"] = filter
    }

    let request = NetworkRequest<Page<Podcast>>(
      path: "/api/libraries/\(library.id)/items",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetch(id: String) async throws -> Podcast {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let query: [String: String] = ["expanded": "1"]

    let request = NetworkRequest<Podcast>(
      path: "/api/items/\(id)",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetchFeed(rssURL: String) async throws -> Podcast.Feed {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct FeedRequest: Encodable {
      let rssFeed: String
    }

    struct FeedResponse: Decodable {
      let podcast: Podcast.Feed
    }

    let request = NetworkRequest<FeedResponse>(
      path: "/api/podcasts/feed",
      method: .post,
      body: FeedRequest(rssFeed: rssURL)
    )

    let response = try await networkService.send(request)
    return response.value.podcast
  }

  public func downloadEpisodes(
    podcastID: String,
    episodes: [Podcast.Feed.Episode]
  ) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let payload = episodes.map { episode -> Podcast.Feed.Episode in
      Podcast.Feed.Episode(
        guid: episode.guid,
        title: episode.title,
        subtitle: episode.subtitle,
        description: episode.description,
        descriptionPlain: episode.descriptionPlain,
        pubDate: episode.pubDate,
        episodeType: episode.episodeType,
        season: episode.season,
        episode: episode.episode,
        author: episode.author,
        duration: episode.duration,
        durationSeconds: episode.durationSeconds,
        explicit: episode.explicit,
        publishedAt: episode.publishedAt,
        enclosure: episode.enclosure,
        chaptersUrl: episode.chaptersUrl,
        chaptersType: episode.chaptersType,
        chapters: episode.chapters ?? [],
        cleanUrl: episode.cleanUrl ?? episode.enclosure?.url,
        isDownloading: episode.isDownloading ?? false,
        isDownloaded: episode.isDownloaded ?? false
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/podcasts/\(podcastID)/download-episodes",
      method: .post,
      body: payload
    )

    _ = try await networkService.send(request)
  }
}
