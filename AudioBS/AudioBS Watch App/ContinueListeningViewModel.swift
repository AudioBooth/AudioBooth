import Audiobookshelf
import Combine
import Foundation
import Models
import WatchConnectivity

final class ContinueListeningViewModel: ContinueListeningView.Model {
  private let connectivityManager = WatchConnectivityManager.shared
  private let playerManager = PlayerManager.shared
  override func fetch() async {
    isLoading = true
    defer { isLoading = false }

    do {
      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()

      let continueListeningBooks =
        personalized.sections
        .first(where: { $0.id == "continue-listening" })
        .flatMap { section -> [Book]? in
          if case .books(let books) = section.entities {
            return books
          }
          return nil
        } ?? []

      let userData = try await Audiobookshelf.shared.authentication.fetchMe()
      let progressByBookID = Dictionary(
        uniqueKeysWithValues: userData.mediaProgress.map { ($0.libraryItemId, $0) }
      )

      let items = continueListeningBooks.map { book in
        let timeRemaining: Double
        if let progress = progressByBookID[book.id] {
          timeRemaining = max(0, book.duration - progress.currentTime)
        } else {
          timeRemaining = book.duration
        }

        return BookItem(
          id: book.id,
          title: book.title,
          author: book.authorName ?? "",
          coverURL: book.coverURL,
          timeRemaining: timeRemaining
        )
      }

      await MainActor.run {
        self.books = items
      }
    } catch {
      print("Failed to fetch continue listening: \(error)")
      await MainActor.run {
        self.books = []
      }
    }
  }

  override func playBook(bookID: String) {
    if WCSession.default.isReachable {
      print("iPhone is reachable - sending play command to iPhone")
      connectivityManager.playBook(bookID: bookID)
    } else {
      print("iPhone not reachable - playing locally on watch")
      Task {
        do {
          if let recentItem = try RecentlyPlayedItem.fetch(bookID: bookID) {
            await MainActor.run {
              playerManager.setCurrent(recentItem)
            }
          } else {
            print("No cached item found for bookID: \(bookID)")
          }
        } catch {
          print("Failed to fetch recently played item: \(error)")
        }
      }
    }
  }
}
