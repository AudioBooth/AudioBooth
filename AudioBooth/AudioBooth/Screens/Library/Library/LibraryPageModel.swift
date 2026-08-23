import API
import Foundation
import Models

final class LibraryPageModel: LibraryPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared

  private var fetched: [LibraryView.Item] = []

  private var filter: FilterPicker.Model.Filter?
  private var sortBy: SortBy?
  private var libraryID: String?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 100
  private var loadTask: Task<Void, Never>?

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

    self.filters = FilterPickerModel(currentFilter: filter, source: .library)

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
    guard fetched.isEmpty, loadTask == nil else { return }

    loadTask = Task {
      await loadBooks()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    exitSelection()
    isLoading = true
    isLoadingNextPage = false
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
    guard loadTask == nil else { return }
    loadTask = Task {
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

  override func onFilterPreferenceChanged(_ newFilter: FilterPicker.Model.Filter) {
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
      let filter = self.filter?.queryValue

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

      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

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

      totalCount = response.total
      hasMorePages = (currentPage * itemsPerPage) < response.total
    } catch {
      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      pageLoadFailed = true
      if currentPage == 0 {
        fetched = []
        items = []
      }
    }

    updateActions()
    isLoadingNextPage = false
    isLoading = false
    loadTask = nil
  }

}
