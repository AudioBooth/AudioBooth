import Foundation

public struct ListeningStats: Codable {
  public let totalTime: Double
  public let days: [String: Double]
  public let dayOfWeek: [String: Double]
  public let today: Double
  public let items: [String: BookStats]?
  public let recentSessions: [Session]?

  public struct BookStats: Codable {
    public let id: String
    public let timeListening: Double
    public let mediaMetadata: MediaMetadata

    public struct MediaMetadata: Codable {
      public let title: String
      public let subtitle: String?
      public let authors: [Author]?
      public let narrators: [String]?

      public struct Author: Codable {
        public let id: String
        public let name: String
      }
    }
  }

  public struct Session: Codable {
    public let id: String
    public let libraryItemId: String
    public let displayTitle: String
    public let displayAuthor: String
    public let coverPath: String?
    public let timeListening: Double
    public let updatedAt: Double
  }
}
