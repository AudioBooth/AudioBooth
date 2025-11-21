import Combine
import Foundation

final class PlayerManager: ObservableObject {
  @Published var current: PlayerView.Model?
  @Published var isShowingFullPlayer = false

  static let shared = PlayerManager()

  private static let currentBookIDKey = "currentBookID"

  var isPlayingOnWatch: Bool {
    guard let current else { return false }
    return current is BookPlayerModel && current.isPlaying
  }

  func setCurrent(_ book: WatchBook) {
    if let player = current as? BookPlayerModel, book.id == player.bookID {
      return
    }

    clearCurrent()
    let playerModel = BookPlayerModel(book: book)
    current = playerModel
    UserDefaults.standard.set(book.id, forKey: Self.currentBookIDKey)
  }

  func clearCurrent() {
    current?.stop()
    current = nil
    UserDefaults.standard.removeObject(forKey: Self.currentBookIDKey)
  }
}
