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

  public struct Chapter: Codable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
  }
}
