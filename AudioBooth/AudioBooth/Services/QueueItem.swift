import Foundation

struct QueueItem: Codable, Identifiable, Equatable {
  let bookID: String
  let title: String
  let details: String?
  let coverURL: URL?
  let podcastID: String?

  var id: String { bookID }

  init(from book: BookActionable) {
    self.bookID = book.bookID
    self.title = book.title
    self.details = book.details
    self.coverURL = book.coverURL
    self.podcastID = nil
  }

  init(bookID: String, title: String, details: String?, coverURL: URL?, podcastID: String? = nil) {
    self.bookID = bookID
    self.title = title
    self.details = details
    self.coverURL = coverURL
    self.podcastID = podcastID
  }
}
