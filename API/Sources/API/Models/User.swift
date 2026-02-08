import Foundation

public struct User: Codable, Sendable {
  public let mediaProgress: [MediaProgress]
  public let bookmarks: [Bookmark]
  public let permissions: Permissions
}

extension User {
  public struct MediaProgress: Codable, Sendable {
    public let id: String
    public let libraryItemId: String
    public let episodeId: String?
    public let duration: Double?
    public let progress: Double
    public let ebookProgress: Double?
    public let ebookLocation: String?
    public let isFinished: Bool
    public let startedAt: Int64
    public let finishedAt: Int64?
    public let currentTime: Double
    public let lastUpdate: Int64

    public init(
      id: String,
      libraryItemId: String,
      episodeId: String? = nil,
      duration: Double,
      progress: Double,
      ebookProgress: Double,
      ebookLocation: String?,
      isFinished: Bool,
      startedAt: Int64,
      finishedAt: Int64?,
      currentTime: Double,
      lastUpdate: Int64
    ) {
      self.id = id
      self.libraryItemId = libraryItemId
      self.episodeId = episodeId
      self.duration = duration
      self.progress = progress
      self.ebookProgress = ebookProgress
      self.ebookLocation = ebookLocation
      self.isFinished = isFinished
      self.startedAt = startedAt
      self.finishedAt = finishedAt
      self.currentTime = currentTime
      self.lastUpdate = lastUpdate
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.id = try container.decode(String.self, forKey: .id)
      self.libraryItemId = try container.decode(String.self, forKey: .libraryItemId)
      self.episodeId = try container.decodeIfPresent(String.self, forKey: .episodeId)
      self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
      self.progress = try container.decode(Double.self, forKey: .progress)
      self.ebookProgress = try container.decodeIfPresent(Double.self, forKey: .ebookProgress)
      self.ebookLocation = try? container.decodeIfPresent(String.self, forKey: .ebookLocation)
      self.isFinished = try container.decode(Bool.self, forKey: .isFinished)
      self.startedAt = try container.decode(Int64.self, forKey: .startedAt)
      self.finishedAt = try container.decodeIfPresent(Int64.self, forKey: .finishedAt)
      self.currentTime = try container.decode(Double.self, forKey: .currentTime)
      self.lastUpdate = try container.decode(Int64.self, forKey: .lastUpdate)
    }
  }

  public struct Bookmark: Codable, Sendable {
    public let bookID: String
    public let time: Double
    public let title: String
    public let createdAt: Int64

    public init(bookID: String, time: Double, title: String, createdAt: Int64) {
      self.bookID = bookID
      self.time = time
      self.title = title
      self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
      case bookID = "libraryItemId"
      case time
      case title
      case createdAt
    }
  }

  public struct Permissions: Codable, Sendable {
    public let update: Bool
    public let delete: Bool
    public let download: Bool
  }
}
