import Foundation

public struct Podcast: Codable, Sendable {
  public let id: String
  public let libraryID: String
  public let media: Media
  public let addedAt: Date
  public let updatedAt: Date
  public let numEpisodesIncomplete: Int?
  public let recentEpisode: PodcastEpisode?

  enum CodingKeys: String, CodingKey {
    case id
    case libraryID = "libraryId"
    case media
    case addedAt
    case updatedAt
    case numEpisodesIncomplete
    case recentEpisode
  }

  @MainActor
  public func coverURL(raw: Bool = false) -> URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    var url = serverURL.appendingPathComponent("api/items/\(id)/cover")

    #if os(watchOS)
    url.append(queryItems: [URLQueryItem(name: "format", value: "jpg")])
    #else
    if raw {
      url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    }
    #endif

    return url
  }
}

extension Podcast {
  public var title: String { media.metadata.title }
  public var titleIgnorePrefix: String { media.metadata.titleIgnorePrefix }
  public var author: String? { media.metadata.author }
  public var description: String? { media.metadata.description }
  public var genres: [String]? { media.metadata.genres }
  public var numEpisodes: Int { media.numEpisodes ?? media.episodes?.count ?? 0 }
  public var size: Int64? { media.size }
  public var tags: [String]? { media.tags }
  public var language: String? { media.metadata.language }
  public var feedURL: String? { media.metadata.feedURL }
  public var podcastType: String? { media.metadata.type }
}

extension Podcast {
  public struct Media: Sendable {
    public let metadata: Metadata
    public let numEpisodes: Int?
    public let autoDownloadEpisodes: Bool?
    public let autoDownloadSchedule: String?
    public let lastEpisodeCheck: Date?
    public let maxEpisodesToKeep: Int?
    public let maxNewEpisodesToDownload: Int?
    public let size: Int64?
    public let coverPath: String?
    public let tags: [String]?
    public let episodes: [PodcastEpisode]?

    public struct Metadata: Sendable {
      public let title: String
      public let titleIgnorePrefix: String
      public let author: String?
      public let description: String?
      public let releaseDate: String?
      public let genres: [String]?
      public let feedURL: String?
      public let imageURL: String?
      public let itunesPageURL: String?
      public let itunesID: String?
      public let explicit: Bool?
      public let language: String?
      public let type: String?
    }
  }
}

extension Podcast.Media: Codable {
  enum CodingKeys: String, CodingKey {
    case metadata, numEpisodes, autoDownloadEpisodes, autoDownloadSchedule
    case lastEpisodeCheck, maxEpisodesToKeep, maxNewEpisodesToDownload
    case size, coverPath, tags, episodes
  }
}

extension Podcast.Media.Metadata: Codable {
  enum CodingKeys: String, CodingKey {
    case title, titleIgnorePrefix, author, description, releaseDate, genres
    case feedURL = "feedUrl"
    case imageURL = "imageUrl"
    case itunesPageURL = "itunesPageUrl"
    case itunesID = "itunesId"
    case explicit, language, type
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    titleIgnorePrefix = try container.decodeIfPresent(String.self, forKey: .titleIgnorePrefix) ?? title
    author = try container.decodeIfPresent(String.self, forKey: .author)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
    genres = try container.decodeIfPresent([String].self, forKey: .genres)
    feedURL = try container.decodeIfPresent(String.self, forKey: .feedURL)
    imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
    itunesPageURL = try container.decodeIfPresent(String.self, forKey: .itunesPageURL)
    itunesID = try container.decodeIfPresent(String.self, forKey: .itunesID)
    explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit)
    language = try container.decodeIfPresent(String.self, forKey: .language)
    type = try container.decodeIfPresent(String.self, forKey: .type)
  }
}

extension Podcast {
  public struct Feed: Codable, Sendable {
    public let metadata: Metadata
    public let episodes: [Episode]

    public struct Metadata: Codable, Sendable {
      public let title: String?
      public let author: String?
      public let description: String?
      public let descriptionPlain: String?
      public let image: String?
      public let feedUrl: String?
      public let language: String?
      public let type: String?
      public let link: String?
    }

    public struct Episode: Codable, Sendable, Identifiable {
      public let guid: String
      public let title: String
      public let subtitle: String?
      public let description: String?
      public let descriptionPlain: String?
      public let pubDate: String?
      public let episodeType: String?
      public let season: String?
      public let episode: String?
      public let author: String?
      public let duration: String?
      public let durationSeconds: Double?
      public let explicit: String?
      public let publishedAt: Int64?
      public let enclosure: Enclosure?
      public let chaptersUrl: String?
      public let chaptersType: String?
      public let chapters: [Chapter]?
      public let cleanUrl: String?
      public let isDownloading: Bool?
      public let isDownloaded: Bool?

      public var id: String { guid }

      public init(
        guid: String,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        descriptionPlain: String? = nil,
        pubDate: String? = nil,
        episodeType: String? = nil,
        season: String? = nil,
        episode: String? = nil,
        author: String? = nil,
        duration: String? = nil,
        durationSeconds: Double? = nil,
        explicit: String? = nil,
        publishedAt: Int64? = nil,
        enclosure: Enclosure? = nil,
        chaptersUrl: String? = nil,
        chaptersType: String? = nil,
        chapters: [Chapter]? = nil,
        cleanUrl: String? = nil,
        isDownloading: Bool? = nil,
        isDownloaded: Bool? = nil
      ) {
        self.guid = guid
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.descriptionPlain = descriptionPlain
        self.pubDate = pubDate
        self.episodeType = episodeType
        self.season = season
        self.episode = episode
        self.author = author
        self.duration = duration
        self.durationSeconds = durationSeconds
        self.explicit = explicit
        self.publishedAt = publishedAt
        self.enclosure = enclosure
        self.chaptersUrl = chaptersUrl
        self.chaptersType = chaptersType
        self.chapters = chapters
        self.cleanUrl = cleanUrl
        self.isDownloading = isDownloading
        self.isDownloaded = isDownloaded
      }

      public struct Enclosure: Codable, Sendable {
        public let length: String?
        public let type: String?
        public let url: String
      }

      public struct Chapter: Codable, Sendable {
        public let id: Int?
        public let start: Double?
        public let end: Double?
        public let title: String?
      }
    }
  }
}
