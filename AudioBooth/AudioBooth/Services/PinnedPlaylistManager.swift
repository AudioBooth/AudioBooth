import API
import Combine
import Foundation
import SwiftUI

final class PinnedPlaylistManager: ObservableObject {
  static let shared = PinnedPlaylistManager()

  private let userDefaults = UserDefaults.standard
  private let preferences = UserPreferences.shared

  private init() {
    migrateIfNeeded()
  }

  var pinnedPlaylistID: String? {
    get {
      guard let key else { return nil }
      return userDefaults.string(forKey: key)
    }
    set {
      guard let key else { return }
      objectWillChange.send()

      if let newValue {
        userDefaults.set(newValue, forKey: key)
      } else {
        userDefaults.removeObject(forKey: key)
      }
    }
  }

  func pin(_ playlistID: String) {
    pinnedPlaylistID = playlistID

    if !preferences.homeSections.contains(.pinnedPlaylist) {
      preferences.homeSections.insert(.pinnedPlaylist, at: 0)
    }
  }

  func unpin() {
    pinnedPlaylistID = nil
  }

  func isPinned(_ playlistID: String) -> Bool {
    pinnedPlaylistID == playlistID
  }

  private var key: String? {
    guard let libraryID = Audiobookshelf.shared.libraries.current?.id else { return nil }
    return "pinnedPlaylistID_\(libraryID)"
  }

  private func migrateIfNeeded() {
    let legacyKey = "pinnedPlaylistID"
    guard let legacyValue = userDefaults.string(forKey: legacyKey) else { return }
    guard let key else { return }

    userDefaults.set(legacyValue, forKey: key)
    userDefaults.removeObject(forKey: legacyKey)
  }
}
