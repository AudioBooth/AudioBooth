import Foundation

public enum CastTrackResolver {
  public static func trackAndOffset(
    for time: TimeInterval,
    in intervals: [(startOffset: TimeInterval, duration: TimeInterval)]
  ) -> (index: Int, offset: TimeInterval) {
    guard !intervals.isEmpty else { return (0, max(0, time)) }
    if time <= 0 {
      return (0, 0)
    }
    for (i, track) in intervals.enumerated() {
      let trackEnd = track.startOffset + track.duration
      if time >= track.startOffset && (time < trackEnd || i == intervals.count - 1) {
        let offset = min(max(0, time - track.startOffset), track.duration)
        return (i, offset)
      }
    }
    let last = intervals.count - 1
    return (last, intervals[last].duration)
  }

  public static func trackAndOffset(
    for time: TimeInterval,
    in tracks: [Track]
  ) -> (index: Int, offset: TimeInterval) {
    trackAndOffset(for: time, in: tracks.map { ($0.startOffset, $0.duration) })
  }

  public static func streamURL(
    serverURL: URL,
    sessionID: String,
    trackIndex: Int
  ) -> URL? {
    let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(base)/public/session/\(sessionID)/track/\(trackIndex)")
  }
}

#if DEBUG
extension CastTrackResolver {
  public static func runSelfCheck() {
    let intervals = [(startOffset: 0.0, duration: 100.0), (startOffset: 100.0, duration: 200.0)]
    assert(trackAndOffset(for: -5, in: intervals).index == 0)
    assert(trackAndOffset(for: 0, in: intervals).offset == 0)
    let mid0 = trackAndOffset(for: 50, in: intervals)
    assert(mid0.index == 0 && mid0.offset == 50)
    let start1 = trackAndOffset(for: 100, in: intervals)
    assert(start1.index == 1 && start1.offset == 0)
    let mid1 = trackAndOffset(for: 250, in: intervals)
    assert(mid1.index == 1 && mid1.offset == 150)
    let end1 = trackAndOffset(for: 350, in: intervals)
    assert(end1.index == 1 && end1.offset == 200)
    let url = streamURL(serverURL: URL(string: "https://abs.example.com/")!, sessionID: "sess1", trackIndex: 2)
    assert(url?.absoluteString == "https://abs.example.com/public/session/sess1/track/2")
  }
}
#endif
