import Foundation

nonisolated struct NarrationSource: Sendable {
  struct Track: Sendable {
    let url: URL
    let secondsFromStartOfBook: TimeInterval
    let duration: TimeInterval

    var secondsToEndOfBook: TimeInterval { secondsFromStartOfBook + duration }
  }

  let tracks: [Track]

  func covers(bookTime: TimeInterval) -> Bool {
    guard let last = tracks.last else { return false }
    return bookTime < last.secondsToEndOfBook
  }

  func locate(bookTime: TimeInterval) -> (trackIndex: Int, offsetInTrack: TimeInterval)? {
    for (index, track) in tracks.enumerated() where bookTime < track.secondsToEndOfBook {
      return (index, max(0, bookTime - track.secondsFromStartOfBook))
    }

    guard let last = tracks.indices.last else { return nil }
    return (last, max(0, bookTime - tracks[last].secondsFromStartOfBook))
  }
}
