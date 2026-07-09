import Foundation

public struct ListeningStats: Codable {
  public let totalTime: Double
  public let days: [String: Double]
  public let dayOfWeek: [String: Double]
  public let today: Double
  public let recentSessions: [Session]?
  public let items: [String: Item]?

  public struct Session: Codable {
    public let id: String
    public let libraryItemId: String
    public let displayTitle: String
    public let displayAuthor: String
    public let coverPath: String?
    public let timeListening: Double?
    public let updatedAt: Double
  }

  public struct Item: Codable {
    public let timeListening: Double?
    public let mediaMetadata: MediaMetadata?

    public struct MediaMetadata: Codable {
      public let authors: [Author]?
      public let narrators: [String]?
      public let genres: [String]?
    }

    public struct Author: Codable {
      public let id: String
      public let name: String
    }
  }
}
