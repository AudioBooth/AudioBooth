import API
import Logging
import SwiftUI

final class AuthorsPageModel: AuthorsPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var fetchedAuthors: [AuthorCard.Model] = []

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 50

  init() {
    super.init(
      isLoading: true,
      hasMorePages: true
    )
    self.searchViewModel = SearchViewModel()
  }

  override func onAppear() {
    Task {
      await loadAuthors()
    }
  }

  override func refresh() async {
    currentPage = 0
    hasMorePages = true
    fetchedAuthors.removeAll()
    authors.removeAll()
    await loadAuthors()
  }

  private func loadAuthors() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let response = try await audiobookshelf.authors.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: .name,
        ascending: true
      )

      let authorCards = response.results.map { author in
        AuthorCardModel(author: author)
      }

      if currentPage == 0 {
        fetchedAuthors = authorCards
      } else {
        fetchedAuthors.append(contentsOf: authorCards)
      }

      self.authors = fetchedAuthors
      currentPage += 1

      hasMorePages = (currentPage * itemsPerPage) < response.total

    } catch {
      AppLogger.viewModel.error("Failed to fetch authors: \(error)")
      if currentPage == 0 {
        fetchedAuthors = []
        authors = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
  }

  override func loadNextPageIfNeeded() {
    Task {
      await loadAuthors()
    }
  }
}
