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
    book = container.decodeSkippingFailures(SearchBook.self, forKey: .book)
    podcast = container.decodeSkippingFailures(SearchPodcast.self, forKey: .podcast)
    episodes = container.decodeSkippingFailures(SearchPodcast.self, forKey: .episodes)
    series = container.decodeSkippingFailures(Series.self, forKey: .series)
    authors = container.decodeSkippingFailures(Author.self, forKey: .authors)
    narrators = container.decodeSkippingFailures(Narrator.self, forKey: .narrators)
    tags = container.decodeSkippingFailures(Tag.self, forKey: .tags)
    genres = container.decodeSkippingFailures(Genre.self, forKey: .genres)
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

extension KeyedDecodingContainer {
  /// Decodes an array element by element, so one result the app can't decode
  /// doesn't fail the whole search. A missing or malformed key yields `[]`.
  fileprivate func decodeSkippingFailures<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
    guard var container = try? nestedUnkeyedContainer(forKey: key) else { return [] }

    var results: [T] = []
    while !container.isAtEnd {
      // superDecoder() moves past the element even when decoding it fails.
      guard let elementDecoder = try? container.superDecoder() else { break }
      do {
        results.append(try T(from: elementDecoder))
      } catch {
        AppLogger.network.warning("Skipping search result in \(key.stringValue): \(error)")
      }
    }
    return results
  }
}
