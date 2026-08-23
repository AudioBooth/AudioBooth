import Foundation

public struct FilterData: Codable, Sendable {
  public struct Author: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }
  }

  public struct Series: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }
  }

  public let authors: [Author]
  public let genres: [String]
  public let tags: [String]
  public let series: [Series]
  public let narrators: [String]
  public let languages: [String]
  public let publishers: [String]
  public let publishedDecades: [String]

  enum CodingKeys: String, CodingKey {
    case authors
    case genres
    case tags
    case series
    case narrators
    case languages
    case publishers
    case publishedDecades
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    authors = try container.decodeIfPresent([Author].self, forKey: .authors) ?? []
    genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    series = try container.decodeIfPresent([Series].self, forKey: .series) ?? []
    narrators = try container.decodeIfPresent([String].self, forKey: .narrators) ?? []
    languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
    publishers = try container.decodeIfPresent([String].self, forKey: .publishers) ?? []
    publishedDecades = try container.decodeIfPresent([String].self, forKey: .publishedDecades) ?? []
  }
}
