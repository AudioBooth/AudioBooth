import Foundation

struct WatchBookmark: Codable, Identifiable {
  var id: Int { time }

  let time: Int
  let title: String

  init(time: Int, title: String) {
    self.time = time
    self.title = title
  }

  init?(dictionary: [String: Any]) {
    guard let time = dictionary["time"] as? Int, let title = dictionary["title"] as? String else { return nil }

    self.init(time: time, title: title)
  }
}

final class WatchBookmarkStore {
  static let shared = WatchBookmarkStore()

  private let bookmarksKey = "bookmarks"

  private var bookmarksByBook: [String: [WatchBookmark]]

  private init() {
    guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
      let bookmarksByBook = try? JSONDecoder().decode([String: [WatchBookmark]].self, from: data)
    else {
      self.bookmarksByBook = [:]
      return
    }
    self.bookmarksByBook = bookmarksByBook
  }

  func bookmarks(for bookID: String) -> [WatchBookmark] {
    bookmarksByBook[bookID] ?? []
  }

  func add(_ bookmark: WatchBookmark, for bookID: String) {
    save(bookmarks(for: bookID) + [bookmark], for: bookID)
  }

  func merge(_ synced: [WatchBookmark], keeping inFlightTimes: Set<Int>, for bookID: String) {
    let syncedTimes = Set(synced.map(\.time))
    let inFlight = bookmarks(for: bookID).filter { inFlightTimes.contains($0.time) && !syncedTimes.contains($0.time) }
    save(synced + inFlight, for: bookID)
  }

  private func save(_ bookmarks: [WatchBookmark], for bookID: String) {
    bookmarksByBook[bookID] = bookmarks.sorted { $0.time < $1.time }
    guard let data = try? JSONEncoder().encode(bookmarksByBook) else { return }
    UserDefaults.standard.set(data, forKey: bookmarksKey)
  }
}
