import Audiobookshelf
import Foundation
import SwiftData

@Model
final class AudioTrackInfo {
  var index: Int
  var startOffset: TimeInterval
  var duration: TimeInterval
  var title: String?
  var fileName: String?
  var updatedAt: Date?

  init(from track: PlaySession.Track) {
    self.index = track.index
    self.startOffset = track.startOffset
    self.duration = track.duration
    self.title = track.title
    self.fileName = nil
    self.updatedAt = track.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0 / 1000)) }
  }
}
