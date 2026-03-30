import Foundation

public struct RecentEpisode: Codable, Sendable {
  public let libraryItemID: String
  public let podcastTitle: String
  public let podcastAuthor: String?
  public let episode: PodcastEpisode

  enum CodingKeys: String, CodingKey {
    case libraryItemID = "libraryItemId"
    case episode
    case podcast
  }

  enum PodcastKeys: String, CodingKey {
    case metadata
  }

  enum MetadataKeys: String, CodingKey {
    case title
    case author
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    libraryItemID = try container.decode(String.self, forKey: .libraryItemID)
    episode = try PodcastEpisode(from: decoder)

    let podcastContainer = try container.nestedContainer(keyedBy: PodcastKeys.self, forKey: .podcast)
    let metadataContainer = try podcastContainer.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
    podcastTitle = try metadataContainer.decode(String.self, forKey: .title)
    podcastAuthor = try metadataContainer.decodeIfPresent(String.self, forKey: .author)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(libraryItemID, forKey: .libraryItemID)
    try episode.encode(to: encoder)
  }

  public func coverURL() -> URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/items/\(libraryItemID)/cover")
  }

  public func coverURL(raw: Bool) -> URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    var url = serverURL.appendingPathComponent("api/items/\(libraryItemID)/cover")
    if raw {
      url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    }
    return url
  }
}
