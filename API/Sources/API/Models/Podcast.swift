import Foundation

public struct Podcast: Codable, Sendable {
  public let id: String
  public let media: Media
  public let addedAt: Date
  public let updatedAt: Date
  public let numEpisodesIncomplete: Int?

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
