import API
import Combine
import Foundation
import Models
import SwiftUI

enum AutoDownloadMode: String, CaseIterable {
  case off
  case wifiOnly
  case wifiAndCellular
}

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

  @AppStorage("shakeToExtendTimer")
  var shakeToExtendTimer: Bool = true

  @AppStorage("customTimerMinutes")
  var customTimerMinutes: Int = 1

  @AppStorage("lockScreenNextPreviousUsesChapters")
  var lockScreenNextPreviousUsesChapters: Bool = false

  @AppStorage("lockScreenAllowPlaybackPositionChange")
  var lockScreenAllowPlaybackPositionChange: Bool = true

  @AppStorage("timeRemainingAdjustsWithSpeed")
  var timeRemainingAdjustsWithSpeed: Bool = true

  @AppStorage("chapterProgressionAdjustsWithSpeed")
  var chapterProgressionAdjustsWithSpeed: Bool = false

  @AppStorage("libraryDisplayMode")
  var libraryDisplayMode: BookCard.DisplayMode = .card

  @AppStorage("collapseSeriesInLibrary")
  var collapseSeriesInLibrary: Bool = false

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

  private init() {
    migrateShowListeningStats()
    migrateAutoDownloadBooks()
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
