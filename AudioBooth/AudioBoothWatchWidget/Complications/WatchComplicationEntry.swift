import Foundation
import WidgetKit

struct WatchComplicationEntry: TimelineEntry {
  let date: Date
  let bookTitle: String?
  let progress: Double
  let chapterProgress: Double?
  let timeRemaining: TimeInterval?
  var bookInterval: ClosedRange<Date>? = nil
  var chapterInterval: ClosedRange<Date>? = nil
  var playbackExpiresAt: Date? = nil
  var chapterTitle: String? = nil
  var chapterTimeRemaining: TimeInterval? = nil
  var coverData: Data? = nil
  var relevance: TimelineEntryRelevance? = nil

  static let empty = WatchComplicationEntry(
    date: Date(),
    bookTitle: nil,
    progress: 0,
    chapterProgress: nil,
    timeRemaining: nil
  )
}

struct WatchComplicationState: Codable {
  let bookTitle: String
  let progress: Double
  let chapterProgress: Double?
  let currentTime: Double
  let duration: Double
  let isPlaying: Bool
  var savedAt: Date? = nil
  var playbackRate: Double? = nil
  var chapterStart: Double? = nil
  var chapterEnd: Double? = nil
  var chapterStarts: [Double]? = nil
  var playbackExpiresAt: Date? = nil
  var bookID: String? = nil
  var chapterTitles: [String]? = nil

  var timeRemaining: TimeInterval {
    max(0, duration - currentTime)
  }
}

enum WatchComplicationStorage {
  private static let suiteName = "group.me.jgrenier.audioBS"
  private static let stateKey = "watchComplicationState"

  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: suiteName)
  }

  static func save(_ state: WatchComplicationState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    sharedDefaults?.set(data, forKey: stateKey)
  }

  static func load() -> WatchComplicationState? {
    guard let data = sharedDefaults?.data(forKey: stateKey),
      let state = try? JSONDecoder().decode(WatchComplicationState.self, from: data)
    else { return nil }
    return state
  }

  static func clear() {
    sharedDefaults?.removeObject(forKey: stateKey)
  }

  static func coverURL(for bookID: String) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
      .appending(path: "ComplicationCovers/\(bookID).jpg")
  }

  static func hasCover(for bookID: String) -> Bool {
    guard let url = coverURL(for: bookID) else { return false }
    return FileManager.default.fileExists(atPath: url.path())
  }

  static func saveCover(_ data: Data, for bookID: String) {
    guard let url = coverURL(for: bookID) else { return }
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: url)
  }
}
