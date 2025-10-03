import Audiobookshelf
import Foundation
import SwiftData

@Model
public final class AudioTrackInfo {
  public var index: Int
  public var startOffset: TimeInterval
  public var duration: TimeInterval
  public var title: String?
  public var updatedAt: Date?
  public var ext: String?
  public var size: Int64?
  public var streamingURL: URL?
  public var relativePath: URL?

  public init(from streamingTrack: PlaySession.StreamingTrack) {
    self.index = streamingTrack.track.index
    self.startOffset = streamingTrack.track.startOffset
    self.duration = streamingTrack.track.duration
    self.title = streamingTrack.track.title
    self.updatedAt = streamingTrack.track.updatedAt.map {
      Date(timeIntervalSince1970: TimeInterval($0 / 1000))
    }
    self.ext = streamingTrack.track.metadata?.ext
    self.size = streamingTrack.track.metadata?.size
    self.streamingURL = streamingTrack.url
    self.relativePath = nil
  }

  public var localPath: URL? {
    guard let relativePath else { return nil }

    guard
      let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      return nil
    }

    let fileURL = documentsURL.appendingPathComponent(relativePath.relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return fileURL
  }

  public var url: URL? {
    return localPath ?? streamingURL
  }
}
