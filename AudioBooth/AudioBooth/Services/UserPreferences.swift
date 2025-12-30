import API
import Combine
import Foundation
import Models
import SwiftUI

final class UserPreferences: ObservableObject {
  static let shared = UserPreferences()

  @AppStorage("homeSections")
  var homeSections: [HomeSection] = HomeSection.defaultCases

  @AppStorage("autoDownloadBooks")
  var autoDownloadBooks: AutoDownloadMode = .off

  @AppStorage("removeDownloadOnCompletion")
  var removeDownloadOnCompletion: Bool = false

  @AppStorage("skipForwardInterval")
  var skipForwardInterval: Double = 30.0

  @AppStorage("skipBackwardInterval")
  var skipBackwardInterval: Double = 30.0

  @AppStorage("smartRewindInterval")
  var smartRewindInterval: Double = 30.0

  @AppStorage("shakeSensitivity")
  var shakeSensitivity: ShakeSensitivity = .medium

  @AppStorage("customTimerMinutes")
  var customTimerMinutes: Int = 1

  @AppStorage("timerFadeOut")
  var timerFadeOut: Double = 30.0

  @AppStorage("lockScreenNextPreviousUsesChapters")
  var lockScreenNextPreviousUsesChapters: Bool = false

  @AppStorage("lockScreenAllowPlaybackPositionChange")
  var lockScreenAllowPlaybackPositionChange: Bool = true

  @AppStorage("timeRemainingAdjustsWithSpeed")
  var timeRemainingAdjustsWithSpeed: Bool = true

  @AppStorage("chapterProgressionAdjustsWithSpeed")
  var chapterProgressionAdjustsWithSpeed: Bool = false

  @AppStorage("showFullBookDuration")
  var showFullBookDuration: Bool = false

  @AppStorage("libraryDisplayMode")
  var libraryDisplayMode: BookCard.DisplayMode = .card

  @AppStorage("collapseSeriesInLibrary")
  var collapseSeriesInLibrary: Bool = false

  @AppStorage("groupSeriesInOffline")
  var groupSeriesInOffline: Bool = false

  @AppStorage("librarySortBy")
  var librarySortBy: BooksService.SortBy = .title

  @AppStorage("librarySortAscending")
  var librarySortAscending: Bool = true

  @AppStorage("libraryFilter")
  var libraryFilter: LibraryPageModel.Filter = .all

  @AppStorage("showNFCTagWriting")
  var showNFCTagWriting: Bool = false

  @AppStorage("showDebugSection")
  var showDebugSection: Bool = false

  @AppStorage("accentColor")
  var accentColor: Color?

  @AppStorage("autoTimerDuration")
  var autoTimerDuration: TimeInterval = 0

  @AppStorage("autoTimerWindowStart")
  var autoTimerWindowStart: Int = 22 * 60

  @AppStorage("autoTimerWindowEnd")
  var autoTimerWindowEnd: Int = 6 * 60

  private init() {
    migrateShowListeningStats()
    migrateAutoDownloadBooks()
    migrateShakeToExtendTimer()
  }

  private func migrateShowListeningStats() {
    if UserDefaults.standard.bool(forKey: "showListeningStats") == true {
      UserDefaults.standard.removeObject(forKey: "showListeningStats")

      homeSections.insert(.listeningStats, at: 0)
    }
  }

  private func migrateAutoDownloadBooks() {
    if UserDefaults.standard.object(forKey: "autoDownloadBooks") is Bool {
      let wasEnabled = UserDefaults.standard.bool(forKey: "autoDownloadBooks")
      UserDefaults.standard.removeObject(forKey: "autoDownloadBooks")
      autoDownloadBooks = wasEnabled ? .wifiAndCellular : .off
    }
  }

  private func migrateShakeToExtendTimer() {
    if UserDefaults.standard.object(forKey: "shakeToExtendTimer") is Bool {
      let wasEnabled = UserDefaults.standard.bool(forKey: "shakeToExtendTimer")
      UserDefaults.standard.removeObject(forKey: "shakeToExtendTimer")
      shakeSensitivity = wasEnabled ? .medium : .off
    }
  }
}

extension Array: @retroactive RawRepresentable where Element: Codable {
  public init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8),
      let result = try? JSONDecoder().decode([Element].self, from: data)
    else {
      return nil
    }
    self = result
  }

  public var rawValue: String {
    guard let data = try? JSONEncoder().encode(self),
      let result = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return result
  }
}

extension Color: @retroactive RawRepresentable {
  public init?(rawValue: String) {
    guard
      let data = Data(base64Encoded: rawValue),
      let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
    else {
      return nil
    }

    self = Color(color)
  }

  public var rawValue: String {
    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(self), requiringSecureCoding: false)
    else {
      return ""
    }

    return data.base64EncodedString()
  }
}

enum AutoDownloadMode: String, CaseIterable {
  case off
  case wifiOnly
  case wifiAndCellular
}

enum ShakeSensitivity: String, CaseIterable {
  case off
  case veryLow
  case low
  case medium
  case high
  case veryHigh

  var threshold: Double {
    switch self {
    case .off: return 0
    case .veryLow: return 2.7
    case .low: return 2.0
    case .medium: return 1.5
    case .high: return 1.3
    case .veryHigh: return 1.1
    }
  }

  var isEnabled: Bool {
    self != .off
  }
}
