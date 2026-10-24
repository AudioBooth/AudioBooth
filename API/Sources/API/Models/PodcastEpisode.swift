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
  public let audioTrack: AudioTrack?
  public let audioFile: AudioFile?

  public struct AudioFile: Codable, Sendable {
    public let duration: Double?
  }

  public struct Chapter: Codable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
  }
}

extension PodcastEpisode {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    season = try container.decodeIfPresent(String.self, forKey: .season)
    episode = try container.decodeIfPresent(String.self, forKey: .episode)
    episodeType = try container.decodeIfPresent(String.self, forKey: .episodeType)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    publishedAt = try container.decodeIfPresent(Int64.self, forKey: .publishedAt)
    size = try container.decodeIfPresent(Int64.self, forKey: .size)
    chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters)
    audioTrack = try container.decodeIfPresent(AudioTrack.self, forKey: .audioTrack)
    audioFile = try container.decodeIfPresent(AudioFile.self, forKey: .audioFile)

    duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? audioFile?.duration
  }
}
