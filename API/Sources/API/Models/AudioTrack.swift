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
