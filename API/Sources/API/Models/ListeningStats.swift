import Foundation

public struct ListeningStats: Codable {
  public let totalTime: Double
  public let days: [String: Double]
  public let today: Double
  public let items: [String: Item]?

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
