import API
import Foundation
import Models

final class LibraryPageModel: LibraryPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let downloadManager = DownloadManager.shared

  private var fetched: [BookCard.Model] = []

  private var filter: Filter?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 100

  private var filterData: FilterData? {
    didSet {
      updateFilterOptions()
    }
  }

  init() {
    let preferences = UserPreferences.shared
    self.filter = preferences.libraryFilter == .all ? nil : preferences.libraryFilter

    super.init(
      hasMorePages: true,
      isRoot: true,
      sortBy: preferences.librarySortBy,
      search: SearchViewModel(),
      title: "Library"
    )

    self.ascending = preferences.librarySortAscending

    createFilterPickerModel()
  }

  init(destination: NavigationDestination) {
    switch destination {
    case .series(let id, let name):
      self.filter = .series(id, name)
      super.init(
        hasMorePages: true,
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .author(let id, let name):
      self.filter = .authors(id, name)
      super.init(
        hasMorePages: true,
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .narrator(let name):
      self.filter = .narrators(name)
      super.init(
        hasMorePages: true,
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .genre(let name):
      self.filter = .genres(name)
      super.init(
        hasMorePages: true,
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .tag(let name):
      self.filter = .tags(name)
      super.init(
        hasMorePages: true,
        isRoot: false,
        sortBy: nil,
        title: name
      )
    case .book, .playlist, .collection, .offline, .stats:
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
    isLoading = true
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

    if isRoot {
      let preferences = UserPreferences.shared
      preferences.librarySortBy = sortBy
      preferences.librarySortAscending = ascending
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

  override func onDownloadAllTapped() {
    Task {
      for book in books {
        guard downloadManager.downloadStates[book.id] != .downloaded else { continue }

        if let localBook = try? LocalBook.fetch(bookID: book.id) {
          try? localBook.download()
        } else {
          let remoteBook = try? await audiobookshelf.books.fetch(id: book.id)
          try? remoteBook?.download()
        }
      }
    }
  }

  override func onFilterButtonTapped() {
    showingFilterSelection = true
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

      case .all, nil:
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

    filters = FilterPickerModel(
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
    guard let filters, let filterData else { return }

    filters.authors = filterData.authors
    filters.genres = filterData.genres.sorted()
    filters.narrators = filterData.narrators.sorted()
    filters.series = filterData.series
    filters.tags = filterData.tags.sorted()
    filters.languages = filterData.languages.sorted()
    filters.publishers = filterData.publishers.sorted()
    filters.publishedDecades = filterData.publishedDecades.sorted(by: >)
  }

  private func applyFilter(_ newFilter: Filter) {
    guard filter != newFilter else { return }

    filter = newFilter
    filters?.selectedFilter = newFilter

    if isRoot {
      UserPreferences.shared.libraryFilter = newFilter
    }

    Task {
      await refresh()
    }
  }

  private func clearFilter() {
    guard filter != nil else { return }

    filter = nil
    filters?.selectedFilter = nil

    if isRoot {
      UserPreferences.shared.libraryFilter = .all
    }

    Task {
      await refresh()
    }
  }
}

extension LibraryPageModel {
  enum Filter: Equatable {
    case all
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

extension LibraryPageModel.Filter: RawRepresentable, Codable {
  enum CodingKeys: String, CodingKey {
    case type
    case value1
    case value2
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "all":
      self = .all
    case "progress":
      let value = try container.decode(String.self, forKey: .value1)
      self = .progress(value)
    case "series":
      let id = try container.decode(String.self, forKey: .value1)
      let name = try container.decode(String.self, forKey: .value2)
      self = .series(id, name)
    case "authors":
      let id = try container.decode(String.self, forKey: .value1)
      let name = try container.decode(String.self, forKey: .value2)
      self = .authors(id, name)
    case "narrators":
      let value = try container.decode(String.self, forKey: .value1)
      self = .narrators(value)
    case "genres":
      let value = try container.decode(String.self, forKey: .value1)
      self = .genres(value)
    case "tags":
      let value = try container.decode(String.self, forKey: .value1)
      self = .tags(value)
    case "languages":
      let value = try container.decode(String.self, forKey: .value1)
      self = .languages(value)
    case "publishers":
      let value = try container.decode(String.self, forKey: .value1)
      self = .publishers(value)
    case "publishedDecades":
      let value = try container.decode(String.self, forKey: .value1)
      self = .publishedDecades(value)
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown filter type"
        )
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .all:
      try container.encode("all", forKey: .type)
    case .progress(let value):
      try container.encode("progress", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .series(let id, let name):
      try container.encode("series", forKey: .type)
      try container.encode(id, forKey: .value1)
      try container.encode(name, forKey: .value2)
    case .authors(let id, let name):
      try container.encode("authors", forKey: .type)
      try container.encode(id, forKey: .value1)
      try container.encode(name, forKey: .value2)
    case .narrators(let value):
      try container.encode("narrators", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .genres(let value):
      try container.encode("genres", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .tags(let value):
      try container.encode("tags", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .languages(let value):
      try container.encode("languages", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .publishers(let value):
      try container.encode("publishers", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .publishedDecades(let value):
      try container.encode("publishedDecades", forKey: .type)
      try container.encode(value, forKey: .value1)
    }
  }

  public init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8),
      let result = try? JSONDecoder().decode(LibraryPageModel.Filter.self, from: data)
    else {
      return nil
    }
    self = result
  }

  public var rawValue: String {
    guard let data = try? JSONEncoder().encode(self),
      let result = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return result
  }
}
