import Audiobookshelf
import Combine
import Foundation
import Models
import WatchConnectivity

final class ContinueListeningViewModel: ContinueListeningView.Model {
  private let connectivityManager = WatchConnectivityManager.shared
  private let playerManager = PlayerManager.shared

  override init(books: [BookItem] = [], isLoading: Bool = false) {
    super.init(books: books, isLoading: isLoading)
    loadCachedBooks()
  }

  private func loadCachedBooks() {
    do {
      let recentItems = try RecentlyPlayedItem.fetchAll()

      let items = recentItems.compactMap { item -> BookItem? in
        guard let mediaProgress = try? MediaProgress.getOrCreate(for: item.bookID) else {
          return nil
        }

        let timeRemaining = max(0, item.playSessionInfo.duration - mediaProgress.currentTime)

        return BookItem(
          id: item.bookID,
          title: item.title,
          author: item.author ?? "",
          coverURL: item.coverURL,
          timeRemaining: timeRemaining,
          isDownloaded: item.playSessionInfo.isDownloaded
        )
      }

      books = items
      print("Loaded \(items.count) cached books")
    } catch {
      print("Failed to load cached books: \(error)")
    }
  }

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

      let items = await MainActor.run {
        continueListeningBooks.map { book in
          let timeRemaining: Double
          if let progress = progressByBookID[book.id] {
            timeRemaining = max(0, book.duration - progress.currentTime)
          } else {
            timeRemaining = book.duration
          }

          let isDownloaded: Bool
          if let item = try? RecentlyPlayedItem.fetch(bookID: book.id) {
            isDownloaded = item.playSessionInfo.isDownloaded
          } else {
            isDownloaded = false
          }

          return BookItem(
            id: book.id,
            title: book.title,
            author: book.authorName ?? "",
            coverURL: book.coverURL,
            timeRemaining: timeRemaining,
            isDownloaded: isDownloaded
          )
        }
      }

      await MainActor.run {
        self.books = items
      }
    } catch {
      print("Failed to fetch continue listening: \(error)")
    }
  }

  override func playBook(bookID: String) {
    #if DEBUG
      let forceLocalPlayback = true  // Set to false to test with iPhone
    #else
      let forceLocalPlayback = false
    #endif

    if !forceLocalPlayback && WCSession.default.isReachable {
      print("iPhone is reachable - sending play command to iPhone")
      connectivityManager.playBook(bookID: bookID)
    } else {
      print(
        "Playing locally on watch (forced: \(forceLocalPlayback), reachable: \(WCSession.default.isReachable))"
      )
      Task {
        do {
          let recentItem: RecentlyPlayedItem

          if let existingItem = try await MainActor.run(body: {
            try RecentlyPlayedItem.fetch(bookID: bookID)
          }) {
            recentItem = existingItem
          } else {
            print("No cached item found, creating from server...")

            // Fetch book info and create session
            let session = try await Audiobookshelf.shared.sessions.start(
              itemID: bookID,
              forceTranscode: false
            )

            // Find book details from continue listening list
            guard let book = books.first(where: { $0.id == bookID }) else {
              print("Book not found in continue listening list")
              return
            }

            let playSessionInfo = PlaySessionInfo(from: session)

            recentItem = RecentlyPlayedItem(
              bookID: bookID,
              title: book.title,
              author: book.author,
              coverURL: book.coverURL,
              playSessionInfo: playSessionInfo
            )

            try await MainActor.run {
              try recentItem.save()
            }
          }

          await MainActor.run {
            playerManager.setCurrent(recentItem)
            playerManager.isShowingFullPlayer = true
          }
        } catch {
          print("Failed to setup playback: \(error)")
        }
      }
    }
  }
}
