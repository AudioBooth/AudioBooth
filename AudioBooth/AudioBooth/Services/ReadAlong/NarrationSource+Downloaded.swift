import Foundation
import Models

extension NarrationSource {
  init?(downloaded tracks: [Models.Track]) {
    let local =
      tracks
      .sorted { $0.startOffset < $1.startOffset }
      .compactMap { track -> Track? in
        guard let url = track.localPath else { return nil }
        return Track(
          url: url,
          secondsFromStartOfBook: track.startOffset,
          duration: track.duration
        )
      }

    guard !local.isEmpty, local.count == tracks.count else { return nil }
    self.init(tracks: local)
  }
}
