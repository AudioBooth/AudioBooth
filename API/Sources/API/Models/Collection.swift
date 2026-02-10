import Foundation

public struct Collection: Codable, Sendable, CollectionLike {
  public let id: String
  public let name: String
  public let libraryID: String
  public let description: String?
  public let books: [Book]
  public let lastUpdate: Date
  public let createdAt: Date

  public var itemCount: Int { books.count }

  public var covers: [URL] {
    books.compactMap { $0.coverURL() }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, books
    case libraryID = "libraryId"
    case lastUpdate, createdAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    libraryID = try container.decode(String.self, forKey: .libraryID)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    books = try container.decode([Book].self, forKey: .books)

    let lastUpdateMs = try container.decode(Int64.self, forKey: .lastUpdate)
    lastUpdate = Date(timeIntervalSince1970: Double(lastUpdateMs) / 1000.0)

    let createdAtMs = try container.decode(Int64.self, forKey: .createdAt)
    createdAt = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
  }
}
