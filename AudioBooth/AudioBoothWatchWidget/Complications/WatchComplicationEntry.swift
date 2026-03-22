import Foundation
import WidgetKit

struct WatchComplicationEntry: TimelineEntry {
  let date: Date
  let bookTitle: String?
  let progress: Double
  let chapterProgress: Double?
  let timeRemaining: TimeInterval?
  let isPlaying: Bool

  static let empty = WatchComplicationEntry(
    date: Date(),
    bookTitle: nil,
    progress: 0,
    chapterProgress: nil,
    timeRemaining: nil,
    isPlaying: false
  )
}

struct WatchComplicationState: Codable {
  let bookTitle: String
  let progress: Double
  let chapterProgress: Double?
  let currentTime: Double
  let duration: Double
  let isPlaying: Bool

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
}
