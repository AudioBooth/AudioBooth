import API
import Foundation

final class PodcastLibraryPageModel: LibraryPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var fetched: [BookCard.Model] = []
  private var sortBy: SortBy = .title
  private var filter: LibraryPageModel.Filter?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 100

  init() {
    let preferences = UserPreferences.shared
    self.filter = preferences.libraryFilter == .all ? nil : preferences.libraryFilter

    super.init(
      hasMorePages: true,
      isRoot: true,
      sortOptions: SortBy.podcastOptions,
      currentSort: .title,
      title: "Podcasts"
    )

    self.filters = FilterPickerModel(currentFilter: filter)
  }

  override func onAppear() {
    guard fetched.isEmpty else { return }

    Task {
      await loadPodcasts()
    }
  }

  override func refresh() async {
    isLoading = true
    currentPage = 0
    hasMorePages = true
    fetched.removeAll()
    books.removeAll()

    await filters?.refresh()
    await loadPodcasts()
  }

  override func onSortOptionTapped(_ sortBy: SortBy) {
    if self.sortBy == sortBy {
      ascending.toggle()
    } else {
      self.sortBy = sortBy
      currentSort = sortBy
      ascending = true
    }

    Task {
      await refresh()
    }
  }

  override func onSearchChanged(_ searchText: String) {
    if searchText.isEmpty {
      books = fetched
    } else {
      let searchTerm = searchText.lowercased()
      books = fetched.filter { item in
        item.title.lowercased().contains(searchTerm)
      }
    }
  }

  override func loadNextPageIfNeeded() {
    Task {
      await loadPodcasts()
    }
  }

  override func onDisplayModeTapped() {
    let preferences = UserPreferences.shared
    preferences.libraryDisplayMode = preferences.libraryDisplayMode == .card ? .row : .card
  }

  override func onFilterButtonTapped() {
    showingFilterSelection = true
  }

  override func onFilterPreferenceChanged(_ newFilter: LibraryPageModel.Filter) {
    let resolved = newFilter == .all ? nil : newFilter
    guard filter != resolved else { return }

    filter = resolved

    Task {
      await refresh()
    }
  }

  private func loadPodcasts() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let filterString: String?

      switch filter {
      case .genres(let name):
        let encoded = Data(name.utf8).base64EncodedString()
        filterString = "genres.\(encoded)"
      case .tags(let name):
        let encoded = Data(name.utf8).base64EncodedString()
        filterString = "tags.\(encoded)"
      case .languages(let name):
        let encoded = Data(name.utf8).base64EncodedString()
        filterString = "languages.\(encoded)"
      case .progress(let name):
        let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let encoded = Data(id.utf8).base64EncodedString()
        filterString = "progress.\(encoded)"
      case .all, nil:
        filterString = nil
      default:
        filterString = nil
      }

      let response = try await audiobookshelf.podcasts.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: sortBy,
        ascending: ascending,
        filter: filterString
      )

      let cards = response.results.map { podcast in
        PodcastCardModel(podcast, sortBy: sortBy)
      }

      if currentPage == 0 {
        fetched = cards
      } else {
        fetched.append(contentsOf: cards)
      }

      books = fetched

      currentPage += 1
      hasMorePages = (currentPage * itemsPerPage) < response.total
    } catch {
      if currentPage == 0 {
        fetched = []
        books = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
  }
}
