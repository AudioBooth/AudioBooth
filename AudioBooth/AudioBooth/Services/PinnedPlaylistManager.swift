import API
import Combine
import Foundation
import Logging
import Models
import Network
import SwiftUI

final class PinnedPlaylistManager: ObservableObject {
  static let shared = PinnedPlaylistManager()

  struct Config: Codable, Equatable {
    let playlistID: String
    var autoDownload: AutoDownloadMode = .off
    var removeCompleted: Bool = false
  }

  private static let cachedPlaylistKey = "cached_pinned_playlist"

  private let userDefaults = UserDefaults.standard
  private let preferences = UserPreferences.shared

  private var cachedPlaylist: Playlist? {
    get {
      guard let data = userDefaults.data(forKey: Self.cachedPlaylistKey) else { return nil }
      return try? JSONDecoder().decode(Playlist.self, from: data)
    }
    set {
      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        userDefaults.set(data, forKey: Self.cachedPlaylistKey)
      } else {
        userDefaults.removeObject(forKey: Self.cachedPlaylistKey)
      }
    }
  }

  private init() {
    migrateIfNeeded()
  }

  var pinnedPlaylistID: String? {
    config?.playlistID
  }

  var config: Config? {
    get {
      guard let key else { return nil }
      guard let data = userDefaults.data(forKey: key) else { return nil }
      return try? JSONDecoder().decode(Config.self, from: data)
    }
    set {
      guard let key else { return }
      objectWillChange.send()

      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        userDefaults.set(data, forKey: key)
      } else {
        userDefaults.removeObject(forKey: key)
      }
    }
  }

  func pin(_ playlistID: String) {
    config = Config(playlistID: playlistID)

    if !preferences.homeSections.contains(.pinnedPlaylist) {
      preferences.homeSections.insert(.pinnedPlaylist, at: 0)
    }
  }

  func unpin() {
    config = nil
  }

  func isPinned(_ playlistID: String) -> Bool {
    pinnedPlaylistID == playlistID
  }

  func loadCached() -> Playlist? {
    guard let cachedPlaylist, cachedPlaylist.id == pinnedPlaylistID else { return nil }
    return cachedPlaylist
  }

  func fetch() async throws -> Playlist? {
    guard let config else {
      cachedPlaylist = nil
      return nil
    }

    var playlist = try await Audiobookshelf.shared.playlists.fetch(id: config.playlistID)

    if config.removeCompleted {
      playlist = await removeCompletedItems(from: playlist)
    }

    if config.autoDownload != .off {
      autoDownloadItems(from: playlist, mode: config.autoDownload)
    }

    cachedPlaylist = playlist
    return playlist
  }

  private func removeCompletedItems(from playlist: Playlist) async -> Playlist {
    let completedItems = playlist.items.filter { item in
      let id = item.episodeID ?? item.libraryItemID
      return MediaProgress.progress(for: id) >= 1.0
    }

    guard !completedItems.isEmpty else { return playlist }

    let completedIDs = completedItems.map(\.libraryItemID)

    do {
      return try await Audiobookshelf.shared.playlists.removeItems(
        playlistID: playlist.id,
        items: completedIDs
      )
    } catch {
      AppLogger.general.error("Failed to remove completed items from pinned playlist: \(error)")
      return playlist
    }
  }

  private func autoDownloadItems(from playlist: Playlist, mode: AutoDownloadMode) {
    let networkMonitor = NetworkMonitor.shared

    switch mode {
    case .off:
      return
    case .wifiOnly:
      guard networkMonitor.interfaceType == .wifi else { return }
    case .wifiAndCellular:
      guard networkMonitor.isConnected else { return }
    }

    let downloadManager = DownloadManager.shared

    for item in playlist.items {
      guard case .book(let book) = item.libraryItem else { continue }

      let progress = MediaProgress.progress(for: book.id)
      guard progress < 1.0 else { continue }
      guard downloadManager.downloadStates[book.id] != .downloaded else { continue }
      guard !downloadManager.isDownloading(for: book.id) else { continue }

      try? book.download()
    }
  }

  private var key: String? {
    guard let libraryID = Audiobookshelf.shared.libraries.current?.id else { return nil }
    return "pinnedPlaylistConfig_\(libraryID)"
  }

  private func migrateIfNeeded() {
    let legacyKey = "pinnedPlaylistID"
    let legacyPerLibraryPrefix = "pinnedPlaylistID_"

    if let legacyValue = userDefaults.string(forKey: legacyKey) {
      guard let key else { return }
      let config = Config(playlistID: legacyValue)
      if let data = try? JSONEncoder().encode(config) {
        userDefaults.set(data, forKey: key)
      }
      userDefaults.removeObject(forKey: legacyKey)
    }

    if let libraryID = Audiobookshelf.shared.libraries.current?.id {
      let perLibraryKey = "\(legacyPerLibraryPrefix)\(libraryID)"
      if let legacyValue = userDefaults.string(forKey: perLibraryKey) {
        guard let key else { return }
        let config = Config(playlistID: legacyValue)
        if let data = try? JSONEncoder().encode(config) {
          userDefaults.set(data, forKey: key)
        }
        userDefaults.removeObject(forKey: perLibraryKey)
      }
    }
  }
}
