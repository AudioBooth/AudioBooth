import API
import Combine
import Foundation
import Models
import OSLog
import WatchConnectivity

final class ContinueListeningViewModel: ContinueListeningView.Model {
  private var cancellables = Set<AnyCancellable>()

  init() {
    super.init()
    loadCachedBooks()
    observeChanges()
  }

  private func observeChanges() {
    Task { @MainActor in
      for await books in LocalBook.observeAll() {
        updateBooks(from: books)
      }
    }
  }

  private func loadCachedBooks() {
    do {
      let books = try LocalBook.fetchAll()
      updateBooks(from: books)
    } catch {
      AppLogger.viewModel.error("Failed to load cached books: \(error)")
    }
  }

  private func updateBooks(from localBooks: [LocalBook]) {
    let rowModels = localBooks.compactMap { localBook -> ContinueListeningRow.Model? in
      guard localBook.isDownloaded,
        let mediaProgress = try? MediaProgress.fetch(bookID: localBook.bookID)
      else {
        return nil
      }

      let timeRemaining = max(0, localBook.duration - mediaProgress.currentTime)

      return ContinueListeningRowModel(localBook, timeRemaining: timeRemaining)
    }

    self.availableOfflineRows = rowModels
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

      let rowModels = await MainActor.run {
        continueListeningBooks.map { book in
          let timeRemaining: Double
          if let progress = progressByBookID[book.id] {
            timeRemaining = max(0, book.duration - progress.currentTime)
          } else {
            timeRemaining = book.duration
          }

          let isDownloaded: Bool
          if let item = try? LocalBook.fetch(bookID: book.id) {
            isDownloaded = item.isDownloaded
          } else {
            isDownloaded = false
          }

          return ContinueListeningRowModel(
            book, timeRemaining: timeRemaining, isDownloaded: isDownloaded)
        }
      }

      self.continueListeningRows = rowModels
    } catch {
      AppLogger.viewModel.error("Failed to fetch continue listening: \(error)")
    }
  }

}
