import Foundation
import ReadiumShared

nonisolated struct MediaOverlayTimeline: Sendable {
  let overlay: MediaOverlay
  let starts: [TimeInterval]

  private let order: [Int]

  init?(overlay: MediaOverlay, trackStartOffsets: [TimeInterval]) {
    let audioFiles = overlay.audioFiles
    guard audioFiles.count == trackStartOffsets.count else { return nil }

    let trackStarts = Dictionary(uniqueKeysWithValues: zip(audioFiles.map(\.string), trackStartOffsets))
    let starts = overlay.clips.map { (trackStarts[$0.audio.string] ?? 0) + $0.begin }

    self.overlay = overlay
    self.starts = starts
    self.order = starts.indices.sorted { starts[$0] < starts[$1] }
  }

  @concurrent
  static func load(from publication: Publication, trackStartOffsets: [TimeInterval]) async -> MediaOverlayTimeline? {
    guard let overlay = await MediaOverlay.load(from: publication) else { return nil }
    return MediaOverlayTimeline(overlay: overlay, trackStartOffsets: trackStartOffsets)
  }

  func clipIndex(at time: TimeInterval) -> Int? {
    var low = 0
    var high = order.count

    while low < high {
      let middle = (low + high) / 2
      if starts[order[middle]] <= time {
        low = middle + 1
      } else {
        high = middle
      }
    }

    return low > 0 ? order[low - 1] : order.first
  }
}
