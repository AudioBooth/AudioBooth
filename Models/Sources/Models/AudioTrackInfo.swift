import Audiobookshelf
import Foundation
import SwiftData

@Model
public final class AudioTrackInfo {
  public var index: Int
  public var startOffset: TimeInterval
  public var duration: TimeInterval
  public var title: String?
  public var fileName: String?
  public var updatedAt: Date?

  public init(from track: PlaySession.Track) {
    self.index = track.index
    self.startOffset = track.startOffset
    self.duration = track.duration
    self.title = track.title
    self.fileName = nil
    self.updatedAt = track.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0 / 1000)) }
  }
}
