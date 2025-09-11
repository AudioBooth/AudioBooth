import Foundation

public struct User: Codable, Sendable {
  public let mediaProgress: [MediaProgress]
}

extension User {
  public struct MediaProgress: Codable, Sendable {
    public let id: String
    public let libraryItemId: String
    public let progress: Double
    public let currentTime: Double
    public let lastUpdate: Int64
  }
}
