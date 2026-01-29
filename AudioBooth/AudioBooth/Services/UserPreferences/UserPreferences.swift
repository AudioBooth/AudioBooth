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

  @AppStorage("smartRewindOnInterruptionInterval")
  var smartRewindOnInterruptionInterval: Double = 0.0

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

  @AppStorage("showBookProgressBar")
  var showBookProgressBar: Bool = false

  @AppStorage("hideChapterSkipButtons")
  var hideChapterSkipButtons: Bool = false

  @AppStorage("volumeLevel")
  var volumeLevel: Double = 1.0

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

  @AppStorage("iCloudSyncEnabled")
  var iCloudSyncEnabled: Bool = false

  @AppStorage("accentColor")
  var accentColor: Color?

  @AppStorage("autoTimerMode")
  var autoTimerMode: AutoTimerMode = .off

  @AppStorage("autoTimerWindowStart")
  var autoTimerWindowStart: Int = 22 * 60

  @AppStorage("autoTimerWindowEnd")
  var autoTimerWindowEnd: Int = 6 * 60

  @AppStorage("playerOrientation")
  var playerOrientation: PlayerOrientation = .auto

  @AppStorage("colorScheme")
  var colorScheme: ColorSchemeMode = .auto

  @AppStorage("continueSectionSize")
  var continueSectionSize: ContinueSectionSize = .default

  @AppStorage("autoPlayNextInQueue")
  var autoPlayNextInQueue: Bool = true

  let cloud = NSUbiquitousKeyValueStore.default
  var cloudObserver: NSObjectProtocol?
  var localObserver: NSObjectProtocol?
  var isApplyingCloudChanges = false

  private init() {
    migrateShowListeningStats()
    migrateAutoDownloadBooks()
    migrateShakeToExtendTimer()
    migrateAutoTimerDuration()
    migrateVolumeBoost()
    setupCloudSync()
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

  private func migrateAutoTimerDuration() {
    if let duration = UserDefaults.standard.object(forKey: "autoTimerDuration") as? TimeInterval {
      UserDefaults.standard.removeObject(forKey: "autoTimerDuration")
      if duration > 0 {
        autoTimerMode = .duration(duration)
      }
    }
  }

  private func migrateVolumeBoost() {
    guard let rawValue = UserDefaults.standard.string(forKey: "volumeBoost") else { return }
    UserDefaults.standard.removeObject(forKey: "volumeBoost")

    switch rawValue {
    case "none": volumeLevel = 1.0
    case "low": volumeLevel = 1.5
    case "medium": volumeLevel = 2.0
    case "high": volumeLevel = 3.0
    default: break
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

  var displayText: String {
    switch self {
    case .off: "Off"
    case .veryLow: "Very Low"
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    case .veryHigh: "Very High"
    }
  }
}

enum AutoTimerMode: Codable, Equatable, Hashable {
  case off
  case duration(TimeInterval)
  case chapters(Int)
}

extension AutoTimerMode: RawRepresentable {
  init?(rawValue: String) {
    let components = rawValue.components(separatedBy: ":")
    guard let type = components.first else { return nil }

    switch type {
    case "off":
      self = .off
    case "duration":
      guard components.count == 2, let duration = TimeInterval(components[1]) else { return nil }
      self = .duration(duration)
    case "chapters":
      guard components.count == 2, let count = Int(components[1]) else { return nil }
      self = .chapters(count)
    default:
      return nil
    }
  }

  var rawValue: String {
    switch self {
    case .off:
      return "off"
    case .duration(let duration):
      return "duration:\(duration)"
    case .chapters(let count):
      return "chapters:\(count)"
    }
  }
}

enum PlayerOrientation: String, CaseIterable {
  case auto
  case portrait
  case landscape

  var displayText: String {
    switch self {
    case .auto: "Auto"
    case .portrait: "Portrait"
    case .landscape: "Landscape"
    }
  }
}

enum ColorSchemeMode: String, CaseIterable {
  case auto
  case light
  case dark

  var displayText: String {
    switch self {
    case .auto: "Auto"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .auto: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum ContinueSectionSize: Int, CaseIterable {
  case `default` = 120
  case large = 160
  case extraLarge = 200

  var value: CGFloat { CGFloat(rawValue) }

  var displayText: String {
    switch self {
    case .default: "Default"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    }
  }
}
