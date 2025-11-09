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

  public init(
    authors: [Author],
    genres: [String],
    tags: [String],
    series: [Series],
    narrators: [String],
    languages: [String],
    publishers: [String],
    publishedDecades: [String]
  ) {
    self.authors = authors
    self.genres = genres
    self.tags = tags
    self.series = series
    self.narrators = narrators
    self.languages = languages
    self.publishers = publishers
    self.publishedDecades = publishedDecades
  }
}
