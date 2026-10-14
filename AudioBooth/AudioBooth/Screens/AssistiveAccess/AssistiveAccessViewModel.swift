import Foundation
import Models

final class AssistiveAccessViewModel: AssistiveAccessView.Model {
  private let playerManager = PlayerManager.shared

  override func onAppear() {
    loadBooks()
  }

  override func onBookTapped(_ book: Book) {
    guard let localBook = try? LocalBook.fetch(bookID: book.id) else { return }
    playerManager.setCurrent(localBook)
    playerManager.showFullPlayer()
  }

  private func loadBooks() {
    let downloadedBooks = (try? LocalBook.fetchAll().filter { $0.isDownloaded && $0.duration > 0 }) ?? []

    books = UserPreferences.shared.offlineSortOrder.sort(downloadedBooks).map { book in
      Book(
        id: book.bookID,
        title: book.title,
        author: book.authorNames.isEmpty ? nil : book.authorNames,
        coverURL: book.coverURL()
      )
    }
  }
}
