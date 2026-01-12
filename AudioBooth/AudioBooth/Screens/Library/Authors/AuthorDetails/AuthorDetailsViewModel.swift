import API
import Combine
import Foundation
import Logging
import Models

final class AuthorDetailsViewModel: AuthorDetailsView.Model {
  private var authorsService: AuthorsService { Audiobookshelf.shared.authors }

  init(authorID: String, name: String = "") {
    super.init(
      authorID: authorID,
      name: name,
      isLoading: true
    )
  }

  override func onAppear() {
    Task {
      await load()
    }
  }

  private func load() async {
    do {
      let details = try await authorsService.fetchDetails(authorID: authorID)

      let seriesWithBooks = details.series.map { seriesData in
        let books = seriesData.items.map { book in
          BookCardModel(book, sortBy: .publishedYear)
        }

        return AuthorDetailsView.Model.SeriesWithBooks(
          id: seriesData.id,
          name: seriesData.name,
          books: books
        )
      }

      let allBooks = details.libraryItems.map { book in
        BookCardModel(book, sortBy: .publishedYear)
      }

      name = details.name
      description = details.description
      imageURL = details.imageURL
      bookCount = details.libraryItems.count
      series = seriesWithBooks
      self.allBooks = allBooks
      isLoading = false
      error = nil
    } catch {
      AppLogger.viewModel.error("Failed to load author details: \(error)")
      isLoading = false
      self.error = "Failed to load author details. Please try again."
    }
  }
}
