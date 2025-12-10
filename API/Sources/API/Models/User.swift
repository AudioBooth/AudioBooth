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
    public let duration: Double
    public let progress: Double
    public let ebookProgress: Double
    public let isFinished: Bool
    public let currentTime: Double
    public let lastUpdate: Int64

    public init(
      id: String,
      libraryItemId: String,
      duration: Double,
      progress: Double,
      ebookProgress: Double,
      isFinished: Bool,
      currentTime: Double,
      lastUpdate: Int64
    ) {
      self.id = id
      self.libraryItemId = libraryItemId
      self.duration = duration
      self.progress = progress
      self.ebookProgress = ebookProgress
      self.isFinished = isFinished
      self.currentTime = currentTime
      self.lastUpdate = lastUpdate
    }
  }

  public struct Bookmark: Codable, Sendable {
    public let bookID: String
    public let time: Int
    public let title: String
    public let createdAt: Int64

    public init(bookID: String, time: Int, title: String, createdAt: Int64) {
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
  }
}
