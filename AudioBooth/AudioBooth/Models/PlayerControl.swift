import Foundation

enum PlayerControl: String, CaseIterable, Identifiable, Codable {
  case speed
  case timer
  case bookmarks
  case history
  case volume

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .speed: String(localized: "Speed")
    case .timer: String(localized: "Timer")
    case .bookmarks: String(localized: "Bookmarks")
    case .history: String(localized: "History")
    case .volume: String(localized: "Volume")
    }
  }

  var systemImage: String {
    switch self {
    case .speed: "speedometer"
    case .timer: "timer"
    case .bookmarks: "bookmark"
    case .history: "clock.arrow.circlepath"
    case .volume: "speaker.wave.2"
    }
  }

  static var `default`: [PlayerControl] {
    [.speed, .timer, .bookmarks]
  }
}
