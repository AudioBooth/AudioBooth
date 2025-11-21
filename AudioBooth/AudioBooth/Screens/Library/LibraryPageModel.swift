import API
import Foundation
import Models

extension LibraryPageModel {
  enum Filter: Equatable {
    case progress(String)
    case series(String, String)
    case authors(String, String)
    case narrators(String)
    case genres(String)
    case tags(String)
    case languages(String)
    case publishers(String)
    case publishedDecades(String)
  }
}

final class LibraryPageModel: LibraryPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var fetched: [BookCard.Model] = []

  private var filter: Filter?

  private var currentPage: Int = 0
  private var hasMorePages: Bool = true
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 50

  private var filterData: FilterData? {
    didSet {
      updateFilterOptions()
    }
  }

  var filterPickerModel: FilterPickerModel?

  init() {
    self.filter = nil

    super.init(
      isRoot: true,
      search: SearchViewModel(),
      title: "Library"
    )

    createFilterPickerModel()
  }

  init(destination: NavigationDestination) {
    switch destination {
    case .series(let id, let name):
      self.filter = .series(id, name)
      super.init(
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .author(let id, let name):
      self.filter = .authors(id, name)
      super.init(
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .narrator(let name):
      self.filter = .narrators(name)
      super.init(
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .genre(let name):
      self.filter = .genres(name)
      super.init(
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .tag(let name):
      self.filter = .tags(name)
      super.init(
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .book, .playlist, .collection, .offline:
      fatalError("LibraryPageModel cannot be initialized with a \(destination) destination")
    }

    self.search = SearchViewModel()
  }

  override func onAppear() {
    guard fetched.isEmpty else { return }

    Task {
      if isRoot && filterData == nil {
        filterData = audiobookshelf.libraries.getCachedFilterData()
        if filterData == nil {
          do {
            filterData = try await audiobookshelf.libraries.fetchFilterData()
          } catch {
            print("Failed to fetch filter data: \(error)")
          }
        }
      }

      await loadBooks()
    }
  }

  override func refresh() async {
    currentPage = 0
    hasMorePages = true
    fetched.removeAll()
    books.removeAll()

    if isRoot {
      do {
        filterData = try await audiobookshelf.libraries.fetchFilterData()
      } catch {
        print("Failed to fetch filter data: \(error)")
      }
    }

    await loadBooks()
  }

  override func onSortByTapped(_ sortBy: BooksService.SortBy) {
    if self.sortBy == sortBy {
      ascending.toggle()
    } else {
      self.sortBy = sortBy
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
      books = fetched.filter { book in
        book.title.lowercased().contains(searchTerm)
      }
    }
  }

  override func loadNextPageIfNeeded() {
    Task {
      await loadBooks()
    }
  }

  override func onDisplayModeTapped() {
    let preferences = UserPreferences.shared
    preferences.libraryDisplayMode = preferences.libraryDisplayMode == .card ? .row : .card
  }

  override func onCollapseSeriesToggled() {
    Task {
      await refresh()
    }
  }

  private func loadBooks() async {
    guard hasMorePages && !isLoadingNextPage && search.searchText.isEmpty else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let filter: String?
      var sortBy = self.sortBy

      switch self.filter {
      case .progress(let name):
        let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let base64ProgressID = Data(id.utf8).base64EncodedString()
        filter = "progress.\(base64ProgressID)"

      case .series(let id, _):
        let base64SeriesID = Data(id.utf8).base64EncodedString()
        filter = "series.\(base64SeriesID)"

      case .authors(let id, _):
        let base64AuthorID = Data(id.utf8).base64EncodedString()
        filter = "authors.\(base64AuthorID)"
        sortBy = .title

      case .narrators(let name):
        let base64NarratorName = Data(name.utf8).base64EncodedString()
        filter = "narrators.\(base64NarratorName)"
        sortBy = .title

      case .genres(let name):
        let base64GenreName = Data(name.utf8).base64EncodedString()
        filter = "genres.\(base64GenreName)"
        sortBy = .title

      case .tags(let name):
        let base64TagName = Data(name.utf8).base64EncodedString()
        filter = "tags.\(base64TagName)"
        sortBy = .title

      case .languages(let name):
        let base64LanguageName = Data(name.utf8).base64EncodedString()
        filter = "languages.\(base64LanguageName)"
        sortBy = .title

      case .publishers(let name):
        let base64PublisherName = Data(name.utf8).base64EncodedString()
        filter = "publishers.\(base64PublisherName)"
        sortBy = .title

      case .publishedDecades(let decade):
        let base64Decade = Data(decade.utf8).base64EncodedString()
        filter = "publishedDecades.\(base64Decade)"
        sortBy = .title

      case nil:
        filter = nil
      }

      let preferences = UserPreferences.shared
      let collapseSeries = isRoot && preferences.collapseSeriesInLibrary
      let response = try await audiobookshelf.books.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: sortBy,
        ascending: ascending,
        collapseSeries: collapseSeries,
        filter: filter
      )

      var bookCards = [BookCardModel]()
      for book in response.results {
        if case .series = self.filter {
          bookCards.append(BookCardModel(book, sortBy: .title))
        } else {
          bookCards.append(BookCardModel(book, sortBy: self.sortBy))
        }
      }

      if currentPage == 0 {
        fetched = bookCards
      } else {
        fetched.append(contentsOf: bookCards)
      }

      if isRoot || search.searchText.isEmpty {
        books = fetched
      } else {
        let searchTerm = search.searchText.lowercased()
        books = fetched.filter { book in
          book.title.lowercased().contains(searchTerm)
        }
      }

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

  private func createFilterPickerModel() {
    let emptyFilterData = FilterData(
      authors: [],
      genres: [],
      tags: [],
      series: [],
      narrators: [],
      languages: [],
      publishers: [],
      publishedDecades: []
    )

    filterPickerModel = FilterPickerModel(
      filterData: filterData ?? emptyFilterData,
      currentFilter: filter,
      onFilterApplied: { [weak self] newFilter in
        self?.applyFilter(newFilter)
      },
      onFilterCleared: { [weak self] in
        self?.clearFilter()
      }
    )
  }

  private func updateFilterOptions() {
    guard let filterPickerModel = filterPickerModel,
      let filterData = filterData
    else { return }

    filterPickerModel.authors = filterData.authors
    filterPickerModel.genres = filterData.genres.sorted()
    filterPickerModel.narrators = filterData.narrators.sorted()
    filterPickerModel.series = filterData.series
    filterPickerModel.tags = filterData.tags.sorted()
    filterPickerModel.languages = filterData.languages.sorted()
    filterPickerModel.publishers = filterData.publishers.sorted()
    filterPickerModel.publishedDecades = filterData.publishedDecades.sorted(by: >)
  }

  private func applyFilter(_ newFilter: Filter) {
    guard filter != newFilter else { return }

    filter = newFilter

    Task {
      await refresh()
    }
  }

  private func clearFilter() {
    guard filter != nil else { return }

    filter = nil

    Task {
      await refresh()
    }
  }
}
