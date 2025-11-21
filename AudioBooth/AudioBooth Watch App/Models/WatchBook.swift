import Foundation

struct WatchBook: Codable, Identifiable {
  let id: String
  let sessionID: String?
  let title: String
  let authorName: String?
  var coverURL: URL?
  let duration: Double
  let chapters: [WatchChapter]
  var tracks: [WatchTrack]
  var currentTime: Double

  var timeRemaining: Double {
    max(0, duration - currentTime)
  }

  var progress: Double {
    guard duration > 0 else { return 0 }
    return currentTime / duration
  }

  var isDownloaded: Bool {
    !tracks.isEmpty && tracks.allSatisfy { $0.relativePath != nil }
  }

  func track(at time: Double) -> WatchTrack? {
    let sortedTracks = tracks.sorted { $0.index < $1.index }
    var accumulatedTime: Double = 0

    for track in sortedTracks {
      if time >= accumulatedTime && time < accumulatedTime + track.duration {
        return track
      }
      accumulatedTime += track.duration
    }

    return sortedTracks.last
  }

  func localURL(for track: WatchTrack) -> URL? {
    guard let relativePath = track.relativePath else { return nil }
    return URL.documentsDirectory.appendingPathComponent(relativePath)
  }

  init(
    id: String,
    sessionID: String? = nil,
    title: String,
    authorName: String?,
    coverURL: URL?,
    duration: Double,
    chapters: [WatchChapter],
    tracks: [WatchTrack] = [],
    currentTime: Double
  ) {
    self.id = id
    self.sessionID = sessionID
    self.title = title
    self.authorName = authorName
    self.coverURL = coverURL
    self.duration = duration
    self.chapters = chapters
    self.tracks = tracks
    self.currentTime = currentTime
  }

  init?(dictionary: [String: Any], currentTime: Double = 0) {
    guard let id = dictionary["id"] as? String,
      let title = dictionary["title"] as? String,
      let duration = dictionary["duration"] as? Double
    else {
      return nil
    }

    self.id = id
    self.sessionID = nil
    self.title = title
    self.authorName = dictionary["author"] as? String
    self.coverURL = (dictionary["coverURL"] as? String).flatMap { URL(string: $0) }
    self.duration = duration
    self.currentTime = currentTime
    self.tracks = []

    if let chaptersData = dictionary["chapters"] as? [[String: Any]] {
      self.chapters = chaptersData.compactMap { WatchChapter(dictionary: $0) }
    } else {
      self.chapters = []
    }
  }
}
