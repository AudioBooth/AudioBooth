import API
import Logging
import SwiftUI

final class SeriesPageModel: SeriesPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let preferences = UserPreferences.shared

  private var fetchedSeries: [SeriesCard.Model] = []
  private var filter: FilterPicker.Model.Filter?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 50
  private var loadTask: Task<Void, Never>?

  init() {
    super.init(hasMorePages: true, currentSort: .name, ascending: true)
    self.search = SearchViewModel()

    let picker = FilterPickerModel(currentFilter: nil, source: .series)
    picker.onFilterSelected = { [weak self] filter in
      self?.onFilterSelected(filter)
    }
    self.filters = picker
  }

  override func onFilterTapped() {
    showingFilterSelection = true
  }

  private func onFilterSelected(_ filter: FilterPicker.Model.Filter?) {
    self.filter = filter
    Task {
      await refresh()
    }
  }

  override func onDisplayModeTapped() {
    preferences.libraryDisplayMode = preferences.libraryDisplayMode == .row ? .card : .row
  }

  override func onSortOptionTapped(_ sortBy: SeriesService.SortBy) {
    if currentSort == sortBy {
      ascending.toggle()
    } else {
      currentSort = sortBy
      ascending = true
    }
    Task {
      await refresh()
    }
  }

  override func onAppear() {
    guard series.isEmpty, loadTask == nil else { return }
    loadTask = Task {
      await loadSeries()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    isLoadingNextPage = false
    currentPage = 0
    self.hasMorePages = true
    fetchedSeries.removeAll()
    series.removeAll()
    await filters?.refresh()
    await loadSeries()
  }

  private func loadSeries() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0
    pageLoadFailed = false

    do {
      let response = try await audiobookshelf.series.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: currentSort,
        ascending: ascending,
        filter: filter?.queryValue
      )

      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      let ignorePrefix = Audiobookshelf.shared.authentication.server?.sortingIgnorePrefix ?? false
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

      totalCount = response.total
      self.hasMorePages = (currentPage * itemsPerPage) < response.total

    } catch {
      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      AppLogger.viewModel.error("Failed to fetch series: \(error)")
      pageLoadFailed = true
      if currentPage == 0 {
        fetchedSeries = []
        series = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
    loadTask = nil
  }

  override func loadNextPageIfNeeded() {
    guard loadTask == nil else { return }
    loadTask = Task {
      await loadSeries()
    }
  }
}
