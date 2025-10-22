import Foundation

public struct Book: Codable, Sendable {
  public let id: String
  public let media: Media
  public let addedAt: Date
  public let updatedAt: Date

  public var coverURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    var url = serverURL.appendingPathComponent("audiobookshelf/api/items/\(id)/cover")

    #if os(watchOS)
      url.append(queryItems: [URLQueryItem(name: "format", value: "jpg")])
    #else
      url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    #endif

    return url
  }

  public var ebookURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL,
      let token = Audiobookshelf.shared.authentication.connection?.token
    else { return nil }

    var url = serverURL.appendingPathComponent("api/items/\(id)/ebook")
    url.append(queryItems: [URLQueryItem(name: "token", value: token)])
    return url
  }
}

extension Book {
  public var title: String { media.metadata.title }
  public var authorName: String? { media.metadata.authorName }
  public var publishedYear: String? { media.metadata.publishedYear }
  public var publisher: String? { media.metadata.publisher }
  public var description: String? { media.metadata.description }
  public var descriptionPlain: String? { media.metadata.descriptionPlain }
  public var genres: [String]? { media.metadata.genres }
  public var series: [Media.Series]? { media.metadata.series }
  public var duration: Double { media.duration ?? 0 }
  public var size: Int64? { media.size }
  public var chapters: [Media.Chapter]? { media.chapters }
  public var tracks: [Media.Track]? { media.tracks }
  public var tags: [String]? { media.tags }

  public enum MediaType {
    case audiobook
    case ebook
  }

  public var mediaType: MediaType {
    (tracks?.count ?? 0) > 0 ? .audiobook : .ebook
  }
}

extension Book {
  public struct Media: Codable, Sendable {
    public let metadata: Metadata
    public let duration: Double?
    public let size: Int64?
    public let chapters: [Chapter]?
    public let tracks: [Track]?
    public let tags: [String]?

    public struct Metadata: Codable, Sendable {
      public let title: String
      public let authors: [Author]?
      public let narrators: [String]?
      public let series: [Series]?
      public let publishedYear: String?
      public let authorName: String?
      public let publisher: String?
      public let description: String?
      public let descriptionPlain: String?
      public let genres: [String]?

      public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        authors = try container.decodeIfPresent([Author].self, forKey: .authors)
        narrators = try container.decodeIfPresent([String].self, forKey: .narrators)
        publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        descriptionPlain = try container.decodeIfPresent(String.self, forKey: .descriptionPlain)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)

        if let seriesArray = try? container.decode([Series].self, forKey: .series) {
          series = seriesArray
        } else if let singleSeries = try? container.decode(Series.self, forKey: .series) {
          series = [singleSeries]
        } else {
          series = nil
        }
      }
    }

    public struct Author: Codable, Sendable {
      public let id: String
      public let name: String
    }

    public struct Series: Codable, Sendable {
      public let id: String
      public let name: String
      public let sequence: String
    }

    public struct Chapter: Codable, Sendable {
      public let id: Int
      public let start: Double
      public let end: Double
      public let title: String
    }

    public struct Track: Codable, Sendable {
      public let index: Int
      public let startOffset: Double
      public let duration: Double
      public let title: String?
      public let updatedAt: Date?
      public let metadata: Metadata?

      public struct Metadata: Codable, Sendable {
        public let filename: String?
        public let ext: String?
        public let size: Int64?
      }
    }
  }
}
