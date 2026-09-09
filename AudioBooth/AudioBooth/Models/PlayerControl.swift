import Foundation

enum PlayerControl: String, CaseIterable, Identifiable, Codable {
  case speed
  case timer
  case bookmarks
  case history
  case volume
  case equalizer
  case lock
  case pageMatch

  var id: String { rawValue }

  var displayName: LocalizedStringResource {
    switch self {
    case .speed: "Speed"
    case .timer: "Timer"
    case .bookmarks: "Bookmarks"
    case .history: "History"
    case .volume: "Volume"
    case .equalizer: "Equalizer"
    case .lock: "Lock"
    case .pageMatch: "Page Match"
    }
  }

  var systemImage: String {
    switch self {
    case .speed: "speedometer"
    case .timer: "moon.zzz.fill"
    case .bookmarks: "bookmark.fill"
    case .history: "clock.arrow.circlepath"
    case .volume: "speaker.wave.2.fill"
    case .equalizer: "slider.vertical.3"
    case .lock: "lock.fill"
    case .pageMatch: "camera.viewfinder"
    }
  }

  static var `default`: [PlayerControl] {
    [.speed, .timer, .bookmarks]
  }
}
