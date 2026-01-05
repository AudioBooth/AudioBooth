import API
import Foundation
import Logging

final class SearchViewModel: SearchView.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var currentSearchTask: Task<Void, Never>?

  private var lastSearch = ""

  override func onSearchChanged(_ searchText: String) {
    guard searchText != lastSearch else { return }
    lastSearch = searchText

    currentSearchTask?.cancel()

    if searchText.isEmpty {
      clearResults()
      return
    }

    currentSearchTask = Task {
      await performSearch(query: searchText)
    }
  }

  private func clearResults() {
    books = []
    series = []
    authors = []
    narrators = []
    tags = []
    genres = []
    isLoading = false
  }

  private func performSearch(query: String) async {
    guard !query.isEmpty else {
      clearResults()
      return
    }

    isLoading = true

    do {
      try await Task.sleep(nanoseconds: 5 * 100_000_000)

      guard !Task.isCancelled else { return }

      let searchResult = try await audiobookshelf.search.search(query: query)

      guard !Task.isCancelled else { return }

      books = searchResult.book.map { searchBook in
        BookCardModel(searchBook.libraryItem, sortBy: .title)
      }

      series = searchResult.series.map { searchSeries in
        SeriesCardModel(series: searchSeries)
      }

      authors = searchResult.authors.map { author in
        AuthorCardModel(author: author)
      }

      narrators = searchResult.narrators.map { narrator in
        narrator.name
      }

      tags = searchResult.tags.map { tag in
        tag.name
      }

      genres = searchResult.genres.map { genre in
        genre.name
      }

      isLoading = false
    } catch {
      guard !Task.isCancelled else { return }

      AppLogger.viewModel.error("Failed to perform search: \(error)")
      Toast(error: "Search failed").show()
      clearResults()

      isLoading = false
    }
  }
}
