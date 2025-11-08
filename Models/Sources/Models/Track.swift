import API
import Foundation
import SwiftData

@Model
public final class Track {
  public var index: Int
  public var startOffset: TimeInterval
  public var duration: TimeInterval
  public var title: String?
  public var updatedAt: Date?
  public var ext: String?
  public var size: Int64?
  public var relativePath: URL?

  public init(from streamingTrack: PlaySession.StreamingTrack) {
    self.index = streamingTrack.track.index
    self.startOffset = streamingTrack.track.startOffset
    self.duration = streamingTrack.track.duration
    self.title = streamingTrack.track.title
    self.updatedAt = streamingTrack.track.updatedAt
    self.ext = streamingTrack.track.metadata?.ext
    self.size = streamingTrack.track.metadata?.size
    self.relativePath = nil
  }

  public init(from track: Book.Media.Track) {
    self.index = track.index
    self.startOffset = track.startOffset
    self.duration = track.duration
    self.title = track.title
    self.updatedAt = track.updatedAt
    self.ext = track.metadata?.ext
    self.size = track.metadata?.size
    self.relativePath = nil
  }

  init(
    index: Int,
    startOffset: TimeInterval,
    duration: TimeInterval,
    title: String? = nil,
    updatedAt: Date? = nil,
    ext: String? = nil,
    size: Int64? = nil,
    relativePath: URL? = nil
  ) {
    self.index = index
    self.startOffset = startOffset
    self.duration = duration
    self.title = title
    self.updatedAt = updatedAt
    self.ext = ext
    self.size = size
    self.relativePath = relativePath
  }

  public var localPath: URL? {
    guard let relativePath else { return nil }

    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      return nil
    }

    let fileURL = appGroupURL.appendingPathComponent(relativePath.relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return fileURL
  }
}
