import Foundation

enum PlayerControl: String, CaseIterable, Identifiable, Codable {
  case speed
  case timer
  case bookmarks
  case history
  case volume

  var id: String { rawValue }

  var displayName: LocalizedStringResource {
    switch self {
    case .speed: "Speed"
    case .timer: "Timer"
    case .bookmarks: "Bookmarks"
    case .history: "History"
    case .volume: "Volume"
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
