import Foundation

public struct PlaySession: Codable, Sendable {
  public let id: String
  public let userId: String
  public let libraryItemId: String
  public let currentTime: Double
  public let duration: Double
  public let audioTracks: [Track]?
  public let chapters: [Chapter]?

  public struct Track: Codable, Sendable {
    public let index: Int
    public let startOffset: Double
    public let duration: Double
    public let title: String?
    public let contentUrl: String?
    public let mimeType: String?
    public let codec: String?
    public let metadata: Metadata?
    public let updatedAt: Int64?

    public struct Metadata: Codable, Sendable {
      public let filename: String?
      public let ext: String?
      public let size: Int64?
      public let duration: Double?
    }
  }

  public struct Chapter: Codable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
  }

  public struct StreamingTrack {
    public var track: Track
    public var url: URL
  }

  public var streamingTracks: [StreamingTrack]? {
    guard var serverURL = Audiobookshelf.shared.authentication.serverURL, let audioTracks else {
      return nil
    }

    let baseURL = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    var tracks = [StreamingTrack]()
    for track in audioTracks {
      let streamingPath = "/public/session/\(id)/track/\(track.index)"
      guard let url = URL(string: "\(baseURL)\(streamingPath)") else { return nil }
      tracks.append(StreamingTrack(track: track, url: url))
    }

    return tracks
  }
}
