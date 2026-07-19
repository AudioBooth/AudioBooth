import API
import Foundation
import Models

final class LibraryPageModel: LibraryPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared

  private var fetched: [LibraryView.Item] = []

  private var filter: Filter?
  private var sortBy: SortBy?
  private var libraryID: String?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 100

  init() {
    let preferences = UserPreferences.shared
    self.filter = preferences.libraryFilter == .all ? nil : preferences.libraryFilter
    self.sortBy = preferences.librarySortBy

    super.init(
      hasMorePages: true,
      isRoot: true,
      sortOptions: SortBy.bookOptions,
      currentSort: preferences.librarySortBy,
      showCollapseSeries: true,
      search: SearchViewModel(),
      title: "Library"
    )

    self.ascending = preferences.librarySortAscending

    self.filters = FilterPickerModel(currentFilter: filter)

    self.actions = Self.collectionActions
  }

  init(destination: NavigationDestination) {
    switch destination {
    case .series(let id, let name, let libraryID):
      self.filter = .series(id, name)
      self.libraryID = libraryID
      super.init(
        hasMorePages: true,
        isRoot: false,
        title: name
      )
    case .authorLibrary(let id, let name, let libraryID):
      self.filter = .authors(id, name)
      self.libraryID = libraryID
      super.init(
        hasMorePages: true,
        isRoot: false,
        title: name
      )
    case .narrator(let name, let libraryID):
      self.filter = .narrators(name)
      self.libraryID = libraryID
      super.init(
        hasMorePages: true,
        isRoot: false,
        title: name
      )
    case .genre(let name, let libraryID):
      self.filter = .genres(name)
      self.libraryID = libraryID
      super.init(
        hasMorePages: true,
        isRoot: false,
        title: name
      )
    case .tag(let name, let libraryID):
      self.filter = .tags(name)
      self.libraryID = libraryID
      super.init(
        hasMorePages: true,
        isRoot: false,
        title: name
      )
    case .author, .book, .playlist, .collection, .offline, .stats, .podcast, .podcastFeed:
      fatalError("LibraryPageModel cannot be initialized with a \(destination) destination")
    }

    self.search = SearchViewModel()

    self.actions = Self.collectionActions.union(.playAll)
  }

  private static var collectionActions: LibraryPage.Model.Actions {
    var available: LibraryPage.Model.Actions = [.addToPlaylist]
    if Audiobookshelf.shared.authentication.server?.permissions?.update == true {
      available.insert(.addToCollection)
    }
    return available
  }

  override func onAppear() {
    updateActions()
    guard fetched.isEmpty else { return }

    Task {
      await loadBooks()
    }
  }

  override func refresh() async {
    exitSelection()
    isLoading = true
    currentPage = 0
    hasMorePages = true
    fetched.removeAll()
    items.removeAll()

    if isRoot {
      await filters?.refresh()
    }

    await loadBooks()
  }

  override func onSortOptionTapped(_ sortBy: SortBy) {
    if self.sortBy == sortBy {
      ascending.toggle()
    } else {
      self.sortBy = sortBy
      currentSort = sortBy
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
      items = fetched
    } else {
      let searchTerm = searchText.lowercased()
      items = fetched.filter { item in

        let title: String =
          switch item {
          case .book(let model): model.title
          case .series(let model): model.title
          }

        return title.lowercased().contains(searchTerm)
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
    exitSelection()
    Task {
      await refresh()
    }
  }

  override func onSelectTapped() {
    isSelecting = true
    selectedIDs = []
  }

  override func onCancelSelectTapped() {
    exitSelection()
  }

  override func onSelectAllTapped() {
    if selectedIDs.count == selectableCount {
      selectedIDs = []
    } else {
      selectedIDs = items.compactMap { item in
        if case .book(let model) = item { model.id } else { nil }
      }
    }
  }

  override func onToggleSelection(_ id: String) {
    if let index = selectedIDs.firstIndex(of: id) {
      selectedIDs.remove(at: index)
    } else {
      selectedIDs.append(id)
    }
  }

  override func onAddSelectionTapped(mode: CollectionMode) {
    guard !selectedIDs.isEmpty else { return }
    collectionSelector = CollectionSelectorSheetModel(bookIDs: selectedIDs, mode: mode)
  }

  private func exitSelection() {
    isSelecting = false
    selectedIDs = []
  }

  override func onDownloadAllTapped() {
    for case let .book(model) in items {
      model.contextMenu?.onDownloadTapped()
    }
  }

  override func onPlayAllTapped() {
    play(allBooks)
  }

  override func onPlaySelectedTapped() {
    play(selectedBooks)
    exitSelection()
  }

  override func onResetAllProgressTapped() {
    if isSelecting {
      guard !selectedIDs.isEmpty else { return }
      for book in selectedBooks {
        book.contextMenu?.onResetProgressTapped()
      }
      exitSelection()
    } else {
      for book in allBooks {
        book.contextMenu?.onResetProgressTapped()
      }
      actions.remove(.resetProgress)
      actions.insert(.markAsFinished)
    }
  }

  override func onMarkAllFinishedTapped() {
    if isSelecting {
      guard !selectedIDs.isEmpty else { return }
      for book in selectedBooks {
        book.contextMenu?.onMarkAsFinishedTapped()
      }
      exitSelection()
    } else {
      for book in allBooks {
        book.contextMenu?.onMarkAsFinishedTapped()
      }
      actions.remove(.markAsFinished)
      actions.insert(.resetProgress)
    }
  }

  private var allBooks: [BookCard.Model] {
    items.compactMap { item in
      if case .book(let model) = item { model } else { nil }
    }
  }

  private var selectedBooks: [BookCard.Model] {
    allBooks.filter { selectedIDs.contains($0.id) }
  }

  private func play(_ books: [BookCard.Model]) {
    guard !books.isEmpty else { return }

    let notCompleted = books.filter { MediaProgress.progress(for: $0.id) < 1.0 }
    let source = notCompleted.isEmpty ? books : notCompleted
    let queueItems = source.map { book in
      QueueItem(
        bookID: book.id,
        title: book.title,
        details: book.author,
        coverURL: book.cover.url,
        podcastID: book.podcastID
      )
    }
    playerManager.playAll(queueItems)
  }

  private func updateActions() {
    guard case .series = filter else { return }
    var updatedActions = actions.intersection([.addToPlaylist, .addToCollection, .playAll])
    for case let .book(model) in items {
      let progress = MediaProgress.progress(for: model.id)
      if progress > 0 {
        updatedActions.insert(.resetProgress)
      }
      if progress < 1.0 {
        updatedActions.insert(.markAsFinished)
      }
    }
    actions = updatedActions
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

  private func loadBooks() async {
    guard hasMorePages && !isLoadingNextPage && search.searchText.isEmpty else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0
    pageLoadFailed = false

    do {
      let filter: String?

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

      case .narrators(let name):
        let base64NarratorName = Data(name.utf8).base64EncodedString()
        filter = "narrators.\(base64NarratorName)"

      case .genres(let name):
        let base64GenreName = Data(name.utf8).base64EncodedString()
        filter = "genres.\(base64GenreName)"

      case .tags(let name):
        let base64TagName = Data(name.utf8).base64EncodedString()
        filter = "tags.\(base64TagName)"

      case .languages(let name):
        let base64LanguageName = Data(name.utf8).base64EncodedString()
        filter = "languages.\(base64LanguageName)"

      case .publishers(let name):
        let base64PublisherName = Data(name.utf8).base64EncodedString()
        filter = "publishers.\(base64PublisherName)"

      case .publishedDecades(let decade):
        let base64Decade = Data(decade.utf8).base64EncodedString()
        filter = "publishedDecades.\(base64Decade)"

      case .explicit:
        filter = "explicit"

      case .abridged:
        filter = "abridged"

      case .all, nil:
        filter = nil
      }

      let preferences = UserPreferences.shared
      let collapseSeries = isRoot && preferences.collapseSeriesInLibrary
      let response = try await audiobookshelf.books.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: isRoot ? self.sortBy : nil,
        ascending: ascending,
        collapseSeries: collapseSeries,
        filter: filter,
        libraryID: libraryID
      )

      var newItems = [LibraryView.Item]()
      let ignorePrefix = isRoot && (audiobookshelf.authentication.server?.sortingIgnorePrefix ?? false)
      for book in response.results {
        if let collapsedSeries = book.collapsedSeries {
          let model = SeriesCardModel(collapsedSeries, sortingIgnorePrefix: ignorePrefix)
          newItems.append(.series(model))
        } else {
          let bookCard: BookCardModel
          if case .series = self.filter {
            bookCard = BookCardModel(book, sortBy: .title, options: .showSequence)
          } else if ignorePrefix {
            bookCard = BookCardModel(book, sortBy: self.sortBy, options: .ignorePrefix)
          } else {
            bookCard = BookCardModel(book, sortBy: self.sortBy)
          }
          newItems.append(.book(bookCard))
        }
      }

      if currentPage == 0 {
        fetched = newItems
      } else {
        fetched.append(contentsOf: newItems)
      }

      if isRoot || search.searchText.isEmpty {
        items = fetched
      } else {
        onSearchChanged(search.searchText)
      }

      currentPage += 1

      hasMorePages = (currentPage * itemsPerPage) < response.total
    } catch {
      pageLoadFailed = true
      if currentPage == 0 {
        fetched = []
        items = []
      }
    }

    updateActions()
    isLoadingNextPage = false
    isLoading = false
  }

}

extension LibraryPageModel {
  enum Filter: Equatable {
    case all
    case explicit
    case abridged
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
    case "explicit":
      self = .explicit
    case "abridged":
      self = .abridged
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
    case .explicit:
      try container.encode("explicit", forKey: .type)
    case .abridged:
      try container.encode("abridged", forKey: .type)
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
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(self),
      let result = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return result
  }
}
