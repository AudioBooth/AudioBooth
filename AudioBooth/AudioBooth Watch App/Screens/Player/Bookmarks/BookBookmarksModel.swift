import Foundation
import WatchKit

final class BookBookmarksModel: BookmarksSheet.Model {
  weak var playerModel: BookPlayerModel?

  private let bookID: String
  private let store = WatchBookmarkStore.shared
  private let connectivityManager = WatchConnectivityManager.shared

  init(playerModel: BookPlayerModel) {
    self.playerModel = playerModel
    self.bookID = playerModel.bookID
    super.init()
  }

  override func onAppear() {
    bookmarks = store.bookmarks(for: bookID)

    Task {
      guard let synced = await connectivityManager.fetchBookmarks(bookID: bookID) else { return }

      store.merge(synced, keeping: connectivityManager.bookmarkTimesInFlight(bookID: bookID), for: bookID)
      bookmarks = store.bookmarks(for: bookID)
    }
  }

  override func onAddTapped() {
    guard addBookmark() else { return }

    WKInterfaceDevice.current().play(.success)
  }

  @discardableResult
  func addBookmark(title: String? = nil) -> Bool {
    guard let playerModel else { return false }

    let time = Int(playerModel.current.rounded(.up))
    guard !store.bookmarks(for: bookID).contains(where: { $0.time == time }) else { return false }

    let formatter = DateFormatter()
    formatter.dateFormat = "M/d/yyyy HH:mm"
    let title = title ?? formatter.string(from: Date())

    store.add(WatchBookmark(time: time, title: title), for: bookID)
    connectivityManager.sendBookmark(bookID: bookID, title: title, time: time)
    bookmarks = store.bookmarks(for: bookID)

    return true
  }

  override func onBookmarkTapped(_ bookmark: WatchBookmark) {
    playerModel?.seekToBookmark(at: bookmark.time)
    isPresented = false
  }
}
