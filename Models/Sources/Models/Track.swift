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

  public var filename: String?
  public var ext: String?
  public var size: Int64?

  public var format: String?
  public var bitRate: Int?
  public var codec: String?
  public var channels: Int?
  public var channelLayout: String?
  public var mimeType: String?

  public var relativePath: URL?

  public init(from streamingTrack: PlaySession.StreamingTrack) {
    self.index = streamingTrack.track.index
    self.startOffset = streamingTrack.track.startOffset
    self.duration = streamingTrack.track.duration
    self.title = streamingTrack.track.title
    self.updatedAt = streamingTrack.track.updatedAt

    self.filename = streamingTrack.track.metadata?.filename
    self.ext = streamingTrack.track.metadata?.ext
    self.size = streamingTrack.track.metadata?.size

    self.format = streamingTrack.track.format
    self.bitRate = streamingTrack.track.bitRate
    self.codec = streamingTrack.track.codec
    self.channels = streamingTrack.track.channels
    self.channelLayout = streamingTrack.track.channelLayout
    self.mimeType = streamingTrack.track.mimeType

    self.relativePath = nil
  }

  public init(from track: Book.Media.Track) {
    self.index = track.index
    self.startOffset = track.startOffset
    self.duration = track.duration
    self.title = track.title
    self.updatedAt = track.updatedAt

    self.filename = track.metadata?.filename
    self.ext = track.metadata?.ext
    self.size = track.metadata?.size

    self.format = track.format
    self.bitRate = track.bitRate
    self.codec = track.codec
    self.channels = track.channels
    self.channelLayout = track.channelLayout
    self.mimeType = track.mimeType

    self.relativePath = nil
  }

  public init(
    index: Int,
    startOffset: TimeInterval,
    duration: TimeInterval,
    title: String? = nil,
    updatedAt: Date? = nil,
    filename: String? = nil,
    ext: String? = nil,
    size: Int64? = nil,
    format: String? = nil,
    bitRate: Int? = nil,
    codec: String? = nil,
    channels: Int? = nil,
    channelLayout: String? = nil,
    mimeType: String? = nil,
    relativePath: URL? = nil
  ) {
    self.index = index
    self.startOffset = startOffset
    self.duration = duration
    self.title = title
    self.updatedAt = updatedAt
    self.filename = filename
    self.ext = ext
    self.size = size
    self.format = format
    self.bitRate = bitRate
    self.codec = codec
    self.channels = channels
    self.channelLayout = channelLayout
    self.mimeType = mimeType
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
