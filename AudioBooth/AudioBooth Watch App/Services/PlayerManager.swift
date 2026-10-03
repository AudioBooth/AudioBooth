import Combine
import Foundation
import WidgetKit

final class PlayerManager: ObservableObject {
  @Published var current: PlayerView.Model?
  @Published private(set) var presented: PlayerView.Model?
  @Published var isShowingFullPlayer = false {
    didSet {
      if !isShowingFullPlayer {
        presented = nil
      }
    }
  }

  static let shared = PlayerManager()

  private static let currentBookIDKey = "currentBookID"

  var isPlayingOnWatch: Bool {
    guard let current else { return false }
    return current is BookPlayerModel && current.isPlaying
  }

  func open(_ book: WatchBook) {
    if let player = current as? BookPlayerModel, book.id == player.bookID {
      presented = player
    } else if isPlayingOnWatch {
      presented = BookPlayerModel(book: book)
    } else {
      clearCurrent()
      let player = BookPlayerModel(book: book)
      current = player
      presented = player
      UserDefaults.standard.set(book.id, forKey: Self.currentBookIDKey)
    }

    isShowingFullPlayer = true
  }

  func activate(_ player: BookPlayerModel) {
    guard current !== player else { return }

    clearCurrent()
    current = player
    UserDefaults.standard.set(player.bookID, forKey: Self.currentBookIDKey)
  }

  func clearCurrent() {
    current?.stop()
    current = nil
    UserDefaults.standard.removeObject(forKey: Self.currentBookIDKey)
    WatchConnectivityManager.shared.updateComplication()
  }
}
