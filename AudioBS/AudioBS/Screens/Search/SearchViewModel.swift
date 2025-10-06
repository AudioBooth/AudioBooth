import API
import Foundation

final class SearchViewModel: SearchView.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var currentSearchTask: Task<Void, Never>?

  private let lastSearch = ""

  override func onSearchChanged(_ searchText: String) {
    guard searchText != lastSearch else { return }

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
    isLoading = false
  }

  private func performSearch(query: String) async {
    guard !query.isEmpty else {
      clearResults()
      return
    }

    isLoading = true

    do {
      let searchResult = try await audiobookshelf.search.search(query: query)

      if !Task.isCancelled {
        books = searchResult.book.map { searchBook in
          BookCardModel(searchBook.libraryItem, sortBy: .title)
        }

        series = searchResult.series.map { searchSeries in
          SeriesCardModel(series: searchSeries)
        }

        authors = searchResult.authors.map { author in
          AuthorCardModel(author: author)
        }

        isLoading = false
      }
    } catch {
      if !Task.isCancelled {
        print("Failed to perform search: \(error)")
        Toast(error: "Search failed").show()
        clearResults()
      }
    }
  }
}
