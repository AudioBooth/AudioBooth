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
    guard let playerModel else { return }

    let time = Int(playerModel.current.rounded(.up))
    guard !bookmarks.contains(where: { $0.time == time }) else { return }

    let formatter = DateFormatter()
    formatter.dateFormat = "M/d/yyyy HH:mm"
    let title = formatter.string(from: Date())

    store.add(WatchBookmark(time: time, title: title), for: bookID)
    connectivityManager.sendBookmark(bookID: bookID, title: title, time: time)
    bookmarks = store.bookmarks(for: bookID)

    WKInterfaceDevice.current().play(.success)
  }

  override func onBookmarkTapped(_ bookmark: WatchBookmark) {
    playerModel?.seekToBookmark(at: bookmark.time)
    isPresented = false
  }
}
