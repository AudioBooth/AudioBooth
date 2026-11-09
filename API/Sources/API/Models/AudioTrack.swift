import Foundation

public struct AudioTrack: Codable, Sendable {
  public let index: Int
  public let startOffset: Double
  public let duration: Double
  public let title: String?
  public let updatedAt: Date?
  public let metadata: Metadata?
  public let format: String?
  public let bitRate: Int?
  public let codec: String?
  public let channels: Int?
  public let channelLayout: String?
  public let mimeType: String?
  public let ino: String?

  public struct Metadata: Codable, Sendable {
    public let filename: String?
    public let ext: String?
    public let size: Int64?
  }
}

extension AudioTrack {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 1
    startOffset = try container.decode(Double.self, forKey: .startOffset)
    duration = try container.decode(Double.self, forKey: .duration)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
    format = try container.decodeIfPresent(String.self, forKey: .format)
    bitRate = try container.decodeIfPresent(Int.self, forKey: .bitRate)
    codec = try container.decodeIfPresent(String.self, forKey: .codec)
    channels = try container.decodeIfPresent(Int.self, forKey: .channels)
    channelLayout = try container.decodeIfPresent(String.self, forKey: .channelLayout)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
    ino = try container.decodeIfPresent(String.self, forKey: .ino)
  }
}
