import Foundation

public struct Book: Codable, Sendable {
  public let id: String
  public let media: Media
  public let addedAt: Date
  public let updatedAt: Date
  public let libraryFiles: [LibraryFile]?
  public let collapsedSeries: CollapsedSeries?

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

  public var ebookURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/items/\(id)/ebook")
  }
}

extension Book {
  public var title: String { media.metadata.title }
  public var titleIgnorePrefix: String { media.metadata.titleIgnorePrefix }
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

  public struct MediaType: OptionSet, Sendable {
    public let rawValue: Int

    public static let audiobook = MediaType(rawValue: 1 << 0)
    public static let ebook = MediaType(rawValue: 1 << 1)

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }

  public var mediaType: MediaType {
    var types: MediaType = []
    if let numTracks = media.numTracks ?? tracks?.count, numTracks > 0 {
      types.insert(.audiobook)
    } else if duration > 0 {
      types.insert(.audiobook)
    }
    if media.ebookFile != nil {
      types.insert(.ebook)
    }
    return types
  }
}

extension Book {
  public struct LibraryFile: Codable, Sendable {
    public let ino: String
    public let metadata: Metadata
    public let addedAt: Date
    public let updatedAt: Date
    public let fileType: FileType?

    public struct Metadata: Codable, Sendable {
      public let filename: String
      public let ext: String
      public let path: String
      public let relPath: String
      public let size: Int64
      public let birthtimeMs: Int64
    }
  }

  public struct Media: Codable, Sendable {
    public let metadata: Metadata
    public let duration: Double?
    public let size: Int64?
    public let numTracks: Int?
    public let chapters: [Chapter]?
    public let tracks: [Track]?
    public let tags: [String]?
    public let ebookFile: LibraryFile?
    public let ebookFormat: String?

    public struct Metadata: Sendable {
      public let title: String
      public let titleIgnorePrefix: String
      public let subtitle: String?
      public let authors: [Author]?
      public let narrators: [String]?
      public let series: [Series]?
      public let publishedYear: String?
      public let publishedDate: String?
      public let authorName: String?
      public let narratorName: String?
      public let seriesName: String?
      public let publisher: String?
      public let description: String?
      public let descriptionPlain: String?
      public let genres: [String]?
      public let isbn: String?
      public let asin: String?
      public let language: String?
      public let explicit: Bool?
      public let abridged: Bool?
    }

    public struct Author: Codable, Sendable {
      public let id: String
      public let name: String
    }

    public struct Series: Sendable {
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
      public let format: String?
      public let bitRate: Int?
      public let codec: String?
      public let channels: Int?
      public let channelLayout: String?
      public let mimeType: String?
      public let ino: String?

      public struct Metadata: Codable, Sendable {
        public let filename: String?
        public let ext: String?
        public let size: Int64?
      }
    }
  }

  public struct CollapsedSeries: Codable, Sendable {
    public let id: String
    public let name: String
    public let nameIgnorePrefix: String?
    public let sequence: String?
    public let numBooks: Int
    public let libraryItemIds: [String]
  }
}

extension Book.LibraryFile {
  public enum FileType: String, Codable, Sendable {
    case image
    case audio
    case ebook
    case text
    case metadata
    case unknown

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(RawValue.self)
      self = Self(rawValue: raw) ?? .unknown
    }
  }
}

extension Book.Media.Metadata: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    titleIgnorePrefix = try container.decodeIfPresent(String.self, forKey: .titleIgnorePrefix) ?? title
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    authors = try container.decodeIfPresent([Book.Media.Author].self, forKey: .authors)
    narrators = try container.decodeIfPresent([String].self, forKey: .narrators)
    publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
    publishedDate = try container.decodeIfPresent(String.self, forKey: .publishedDate)
    authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
    narratorName = try container.decodeIfPresent(String.self, forKey: .narratorName)
    seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
    publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    descriptionPlain = try container.decodeIfPresent(String.self, forKey: .descriptionPlain)
    genres = try container.decodeIfPresent([String].self, forKey: .genres)
    isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
    asin = try container.decodeIfPresent(String.self, forKey: .asin)
    language = try container.decodeIfPresent(String.self, forKey: .language)
    explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit)
    abridged = try container.decodeIfPresent(Bool.self, forKey: .abridged)

    if let seriesArray = try? container.decode([Book.Media.Series].self, forKey: .series) {
      series = seriesArray
    } else if let singleSeries = try? container.decode(Book.Media.Series.self, forKey: .series) {
      series = [singleSeries]
    } else {
      series = nil
    }
  }
}

extension Book.Media.Series: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    sequence = try container.decodeIfPresent(String.self, forKey: .sequence) ?? ""
  }
}
