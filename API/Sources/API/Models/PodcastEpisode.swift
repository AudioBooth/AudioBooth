import Foundation

public struct PodcastEpisode: Codable, Sendable {
  public let id: String
  public let title: String
  public let season: String?
  public let episode: String?
  public let episodeType: String?
  public let description: String?
  public let publishedAt: Int64?
  public let duration: Double?
  public let size: Int64?
  public let chapters: [Chapter]?
  public let audioTrack: Track?

  public struct Chapter: Codable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
  }

  public struct Track: Codable, Sendable {
    public let ino: String
    public let metadata: Metadata?

    public struct Metadata: Codable, Sendable {
      public let filename: String?
      public let ext: String?
      public let size: Int64?
    }
  }
}
