import Audiobookshelf
import Combine
import SwiftUI

final class PlayerManager: ObservableObject {
  @Published var current: BookPlayer.Model?
  @Published var isShowingFullPlayer = false

  static let shared = PlayerManager()

  private static let currentBookIDKey = "currentBookID"

  private init() {
    Task { @MainActor in
      await self.restoreLastPlayer()
    }
  }

  private func restoreLastPlayer() async {
    guard current == nil,
      let savedBookID = UserDefaults.standard.string(forKey: Self.currentBookIDKey),
      let recent = try? RecentlyPlayedItem.fetch(bookID: savedBookID)
    else {
      return
    }

    setCurrent(recent)
  }

  var hasActivePlayer: Bool {
    current != nil
  }

  var isPlaying: Bool {
    current?.isPlaying ?? false
  }

  func setCurrent(_ book: RecentlyPlayedItem) {
    if book.bookID == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.closeSession()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.bookID, forKey: Self.currentBookIDKey)
    }
  }

  func setCurrent(_ book: Book) {
    if book.id == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.closeSession()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.id, forKey: Self.currentBookIDKey)
    }
  }

  func clearCurrent() {
    if let currentPlayer = current as? BookPlayerModel {
      currentPlayer.closeSession()
    }
    current = nil
    isShowingFullPlayer = false
    UserDefaults.standard.removeObject(forKey: Self.currentBookIDKey)
  }

  func showFullPlayer() {
    isShowingFullPlayer = true
  }

  func hideFullPlayer() {
    isShowingFullPlayer = false
  }
}
