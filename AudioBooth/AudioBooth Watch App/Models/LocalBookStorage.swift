import Combine
import Foundation

final class LocalBookStorage: ObservableObject {
  static let shared = LocalBookStorage()

  private let booksKey = "local_books"

  @Published private(set) var books: [WatchBook]

  private init() {
    guard let data = UserDefaults.standard.data(forKey: booksKey),
      let books = try? JSONDecoder().decode([WatchBook].self, from: data)
    else {
      self.books = []
      return
    }
    self.books = books
  }

  func saveBooks(_ books: [WatchBook]) {
    let data = try? JSONEncoder().encode(books)
    UserDefaults.standard.set(data, forKey: booksKey)
    self.books = books
  }

  func saveBook(_ book: WatchBook) {
    var updatedBooks = books
    if let index = updatedBooks.firstIndex(where: { $0.id == book.id }) {
      updatedBooks[index] = book
    } else {
      updatedBooks.append(book)
    }
    saveBooks(updatedBooks)
  }

  func deleteBook(_ id: String) {
    var updatedBooks = books
    updatedBooks.removeAll { $0.id == id }
    saveBooks(updatedBooks)
  }

  func updateProgress(for bookID: String, currentTime: Double) {
    var updatedBooks = books
    if let index = updatedBooks.firstIndex(where: { $0.id == bookID }) {
      updatedBooks[index].currentTime = currentTime
      saveBooks(updatedBooks)
    }
  }
}
