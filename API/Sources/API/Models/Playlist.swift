import Foundation

public struct Playlist: Codable, Sendable, CollectionLike {
  public let id: String
  public let name: String
  public let libraryID: String
  public let userID: String
  public let description: String?
  public let lastUpdate: Date
  public let createdAt: Date
  public let items: [PlaylistItem]

  public var books: [Book] {
    items.compactMap {
      if case .book(let book) = $0.libraryItem { return book }
      return nil
    }
  }

  public var itemCount: Int {
    items.count
  }

  public var covers: [URL] {
    items.compactMap { $0.coverURL }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, items
    case libraryID = "libraryId"
    case userID = "userId"
    case lastUpdate, createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    libraryID = try container.decode(String.self, forKey: .libraryID)
    userID = try container.decode(String.self, forKey: .userID)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    items = try container.decode([PlaylistItem].self, forKey: .items)

    let lastUpdateMs = try container.decode(Int64.self, forKey: .lastUpdate)
    lastUpdate = Date(timeIntervalSince1970: Double(lastUpdateMs) / 1000.0)

    let createdAtMs = try container.decode(Int64.self, forKey: .createdAt)
    createdAt = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
  }
}

public struct PlaylistItem: Sendable {
  public let libraryItemID: String
  public let episodeID: String?
  public let libraryItem: LibraryItem
  public let episode: PodcastEpisode?

  public enum LibraryItem: Sendable {
    case book(Book)
    case podcast(Podcast)
  }

  public var coverURL: URL? {
    switch libraryItem {
    case .book(let book): book.coverURL()
    case .podcast(let podcast): podcast.coverURL()
    }
  }

  public var title: String {
    switch libraryItem {
    case .book(let book): book.title
    case .podcast(let podcast): podcast.title
    }
  }
}

extension PlaylistItem: Codable {
  private enum CodingKeys: String, CodingKey {
    case libraryItemID = "libraryItemId"
    case episodeID = "episodeId"
    case libraryItem
    case episode
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    libraryItemID = try container.decode(String.self, forKey: .libraryItemID)
    episodeID = try container.decodeIfPresent(String.self, forKey: .episodeID)
    episode = try container.decodeIfPresent(PodcastEpisode.self, forKey: .episode)

    if episodeID != nil {
      let podcast = try container.decode(Podcast.self, forKey: .libraryItem)
      libraryItem = .podcast(podcast)
    } else {
      let book = try container.decode(Book.self, forKey: .libraryItem)
      libraryItem = .book(book)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(libraryItemID, forKey: .libraryItemID)
    try container.encodeIfPresent(episodeID, forKey: .episodeID)
    try container.encodeIfPresent(episode, forKey: .episode)

    switch libraryItem {
    case .book(let book):
      try container.encode(book, forKey: .libraryItem)
    case .podcast(let podcast):
      try container.encode(podcast, forKey: .libraryItem)
    }
  }
}
