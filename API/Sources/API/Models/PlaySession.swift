import Foundation

public struct PlaySession: Sendable {
  public let id: String
  public let userId: String
  public let libraryItemId: String
  public let episodeId: String?
  public let mediaType: String?
  public let currentTime: Double
  public let duration: Double
  public let audioTracks: [Book.Media.Track]?
  public let chapters: [Book.Media.Chapter]?
  public let libraryItem: LibraryItem

  public enum LibraryItem: Sendable {
    case book(Book)
    case podcast(Podcast)
  }

  public struct StreamingTrack {
    public var track: Book.Media.Track
    public var url: URL
  }
}

extension PlaySession: Codable {
  enum CodingKeys: String, CodingKey {
    case id, userId, libraryItemId, episodeId, mediaType
    case currentTime, duration, audioTracks, chapters, libraryItem
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    userId = try container.decode(String.self, forKey: .userId)
    libraryItemId = try container.decode(String.self, forKey: .libraryItemId)
    episodeId = try container.decodeIfPresent(String.self, forKey: .episodeId)
    mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
    currentTime = try container.decode(Double.self, forKey: .currentTime)
    duration = try container.decode(Double.self, forKey: .duration)
    audioTracks = try container.decodeIfPresent([Book.Media.Track].self, forKey: .audioTracks)
    chapters = try container.decodeIfPresent([Book.Media.Chapter].self, forKey: .chapters)

    if mediaType == "podcast" {
      let podcast = try container.decode(Podcast.self, forKey: .libraryItem)
      libraryItem = .podcast(podcast)
    } else {
      let book = try container.decode(Book.self, forKey: .libraryItem)
      libraryItem = .book(book)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(userId, forKey: .userId)
    try container.encode(libraryItemId, forKey: .libraryItemId)
    try container.encodeIfPresent(episodeId, forKey: .episodeId)
    try container.encodeIfPresent(mediaType, forKey: .mediaType)
    try container.encode(currentTime, forKey: .currentTime)
    try container.encode(duration, forKey: .duration)
    try container.encodeIfPresent(audioTracks, forKey: .audioTracks)
    try container.encodeIfPresent(chapters, forKey: .chapters)

    switch libraryItem {
    case .book(let book):
      try container.encode(book, forKey: .libraryItem)
    case .podcast(let podcast):
      try container.encode(podcast, forKey: .libraryItem)
    }
  }
}
