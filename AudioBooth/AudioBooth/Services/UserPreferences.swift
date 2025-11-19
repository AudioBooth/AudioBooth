import Combine
import Foundation
import Models
import SwiftUI

final class UserPreferences: ObservableObject {
  static let shared = UserPreferences()

  @AppStorage("skipForwardInterval") var skipForwardInterval: Double = 30.0
  @AppStorage("skipBackwardInterval") var skipBackwardInterval: Double = 30.0
  @AppStorage("smartRewindInterval") var smartRewindInterval: Double = 30.0
  @AppStorage("showDebugSection") var showDebugSection: Bool = false
  @AppStorage("libraryDisplayMode") var libraryDisplayMode: BookCard.DisplayMode = .card
  @AppStorage("autoDownloadBooks") var autoDownloadBooks: Bool = false
  @AppStorage("removeDownloadOnCompletion") var removeDownloadOnCompletion: Bool = false
  @AppStorage("showNFCTagWriting") var showNFCTagWriting: Bool = false
  @AppStorage("homeSections") var homeSections: [HomeSection] = HomeSection.defaultCases

  private init() {
    migrateShowListeningStats()
  }

  private func migrateShowListeningStats() {
    if UserDefaults.standard.bool(forKey: "showListeningStats") == true {
      UserDefaults.standard.removeObject(forKey: "showListeningStats")

      homeSections.insert(.listeningStats, at: 0)
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
