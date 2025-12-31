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
    items.map { $0.libraryItem }
  }

  public var covers: [URL] {
    items.compactMap { $0.libraryItem.coverURL() }
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

public struct PlaylistItem: Codable, Sendable {
  public let libraryItemID: String
  public let libraryItem: Book

  private enum CodingKeys: String, CodingKey {
    case libraryItemID = "libraryItemId"
    case libraryItem
  }
}
