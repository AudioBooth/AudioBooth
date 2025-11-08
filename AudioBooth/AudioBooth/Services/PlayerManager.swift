import API
import Combine
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

final class PlayerManager: ObservableObject, Sendable {
  @Published var current: BookPlayer.Model?
  @Published var isShowingFullPlayer = false

  static let shared = PlayerManager()

  private static let currentBookIDKey = "currentBookID"
  private let watchConnectivity = WatchConnectivityManager.shared
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

  private init() {
    if let existingBookID = UserDefaults.standard.string(forKey: Self.currentBookIDKey) {
      sharedDefaults?.set(existingBookID, forKey: Self.currentBookIDKey)
    }

    Task { @MainActor in
      await self.restoreLastPlayer()
    }
  }

  private func restoreLastPlayer() async {
    guard current == nil,
      let savedBookID = UserDefaults.standard.string(forKey: Self.currentBookIDKey),
      let book = try? LocalBook.fetch(bookID: savedBookID)
    else {
      return
    }

    setCurrent(book)
  }

  var hasActivePlayer: Bool {
    current != nil
  }

  var isPlaying: Bool {
    current?.isPlaying ?? false
  }

  func setCurrent(_ book: LocalBook) {
    if book.bookID == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.stopPlayer()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.bookID, forKey: Self.currentBookIDKey)
      sharedDefaults?.set(book.bookID, forKey: Self.currentBookIDKey)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  func setCurrent(_ book: Book) {
    if book.id == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.stopPlayer()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.id, forKey: Self.currentBookIDKey)
      sharedDefaults?.set(book.id, forKey: Self.currentBookIDKey)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  func clearCurrent() {
    if let currentPlayer = current as? BookPlayerModel {
      currentPlayer.stopPlayer()
      currentPlayer.closeSession()
    }
    current = nil
    isShowingFullPlayer = false
    UserDefaults.standard.removeObject(forKey: Self.currentBookIDKey)
    sharedDefaults?.removeObject(forKey: Self.currentBookIDKey)
    watchConnectivity.clearPlaybackState()
    SessionManager.shared.clearSession()
    WidgetCenter.shared.reloadAllTimelines()
  }

  func showFullPlayer() {
    isShowingFullPlayer = true
  }

  func hideFullPlayer() {
    isShowingFullPlayer = false
  }
}

extension PlayerManager: PlayerManagerProtocol {
  func play() {
    current?.onPlayTapped()
  }

  func pause() {
    current?.onPauseTapped()
  }
}
