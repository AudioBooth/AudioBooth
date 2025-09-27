import Foundation

public struct Personalized: Codable {
  public let libraryID: String
  public let sections: [Section]
  public let timestamp: Date

  public init(libraryID: String, sections: [Section], timestamp: Date = Date()) {
    self.libraryID = libraryID
    self.sections = sections
    self.timestamp = timestamp
  }
}

extension Personalized {
  public struct Section: Codable, Identifiable {
    public let id: String
    public let label: String

    public enum Entities: Codable {
      case books([Book])
      case series([Series])
      case authors([Author])
      case unknown
    }
    public let entities: Entities

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)

      id = try container.decode(String.self, forKey: .id)
      label = try container.decode(String.self, forKey: .label)

      enum SectionType: String, Decodable {
        case book
        case series
        case authors
      }

      let typeString = try container.decode(String.self, forKey: .type)
      let type = SectionType(rawValue: typeString)

      switch type {
      case .book:
        let books = try container.decode([Book].self, forKey: .entities)
        entities = .books(books)
      case .series:
        let series = try container.decode([Series].self, forKey: .entities)
        entities = .series(series)
      case .authors:
        let authors = try container.decode([Author].self, forKey: .entities)
        entities = .authors(authors)
      case .none:
        entities = .unknown
      }
    }

    enum CodingKeys: String, CodingKey {
      case id, label, type, entities
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encode(label, forKey: .label)

      switch entities {
      case .books(let books):
        try container.encode("book", forKey: .type)
        try container.encode(books, forKey: .entities)
      case .series(let series):
        try container.encode("series", forKey: .type)
        try container.encode(series, forKey: .entities)
      case .authors(let authors):
        try container.encode("authors", forKey: .type)
        try container.encode(authors, forKey: .entities)
      case .unknown:
        try container.encode("unknown", forKey: .type)
        try container.encode([String](), forKey: .entities)
      }
    }
  }
}
