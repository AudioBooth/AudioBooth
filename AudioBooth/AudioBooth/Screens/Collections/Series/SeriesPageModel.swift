import API
import Logging
import SwiftUI

final class SeriesPageModel: SeriesPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var fetchedSeries: [SeriesCard.Model] = []

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 50

  init() {
    super.init(hasMorePages: true)
    self.search = SearchViewModel()
  }

  override func onAppear() {
    Task {
      await loadSeries()
    }
  }

  override func refresh() async {
    currentPage = 0
    self.hasMorePages = true
    fetchedSeries.removeAll()
    series.removeAll()
    await loadSeries()
  }

  private func loadSeries() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let response = try await audiobookshelf.series.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: .name,
        ascending: true
      )

      let ignorePrefix = Audiobookshelf.shared.libraries.sortingIgnorePrefix
      let seriesCards = response.results.map { series in
        SeriesCardModel(series: series, sortingIgnorePrefix: ignorePrefix)
      }

      if currentPage == 0 {
        fetchedSeries = seriesCards
      } else {
        fetchedSeries.append(contentsOf: seriesCards)
      }

      self.series = fetchedSeries
      currentPage += 1

      self.hasMorePages = (currentPage * itemsPerPage) < response.total

    } catch {
      AppLogger.viewModel.error("Failed to fetch series: \(error)")
      if currentPage == 0 {
        fetchedSeries = []
        series = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
  }

  override func loadNextPageIfNeeded() {
    Task {
      await loadSeries()
    }
  }
}
