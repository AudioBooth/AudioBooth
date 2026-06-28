import Foundation

public struct SearchResponse: Decodable, Sendable {
  public let book: [SearchBook]
  public let podcast: [SearchPodcast]
  public let episodes: [SearchPodcast]
  public let series: [Series]
  public let authors: [Author]
  public let narrators: [Narrator]
  public let tags: [Tag]
  public let genres: [Genre]

  enum CodingKeys: String, CodingKey {
    case book
    case podcast
    case episodes
    case series
    case authors
    case narrators
    case tags
    case genres
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    book = try container.decodeIfPresent([SearchBook].self, forKey: .book) ?? []
    podcast = try container.decodeIfPresent([SearchPodcast].self, forKey: .podcast) ?? []
    episodes = try container.decodeIfPresent([SearchPodcast].self, forKey: .episodes) ?? []
    series = try container.decodeIfPresent([Series].self, forKey: .series) ?? []
    authors = try container.decodeIfPresent([Author].self, forKey: .authors) ?? []
    narrators = try container.decodeIfPresent([Narrator].self, forKey: .narrators) ?? []
    tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
    genres = try container.decodeIfPresent([Genre].self, forKey: .genres) ?? []
  }
}

extension SearchResponse {
  public struct SearchBook: Decodable, Sendable {
    public let libraryItem: Book
  }

  public struct SearchPodcast: Decodable, Sendable {
    public let libraryItem: Podcast
  }

  public struct Narrator: Codable, Sendable {
    public let name: String
    public let numBooks: Int
  }

  public struct Tag: Codable, Sendable {
    public let name: String
    public let numItems: Int
  }

  public struct Genre: Codable, Sendable {
    public let name: String
    public let numItems: Int
  }
}
