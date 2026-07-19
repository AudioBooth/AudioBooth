import API
import Combine
import SwiftUI

struct LibraryPage: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  @ObservedObject var model: Model

  var body: some View {
    if model.isRoot {
      content
        .conditionalSearchable(
          text: $model.search.searchText,
          prompt: "Search books, series, and authors"
        )
        .refreshable {
          await model.refresh()
        }
    } else {
      content
    }
  }

  var content: some View {
    Group {
      if model.isRoot && !model.search.searchText.isEmpty {
        SearchView(model: model.search)
      } else {
        if model.isLoading && model.items.isEmpty {
          ProgressView("Loading books...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty, !model.isLoading, model.filters?.selectedFilter != nil {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "magnifyingglass",
            description: Text("No books match your search.")
          )
        } else if model.items.isEmpty, !model.isLoading {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "books.vertical",
            description: Text("Your library appears to be empty or no library is selected.")
          )
        } else {
          libraryView
        }
      }
    }
    .background(theme.colors.background.page)
    .navigationTitle(model.isSelecting ? selectionTitle : model.title)
    .sheet(isPresented: $model.showingFilterSelection) {
      if let filters = model.filters {
        NavigationStack {
          FilterPicker(model: filters)
        }
      }
    }
    .sheet(item: $model.collectionSelector) { selector in
      CollectionSelectorSheet(model: selector)
    }
    .toolbar {
      if model.isSelecting {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            model.onCancelSelectTapped()
          } label: {
            Text("Cancel")
          }
          .tint(.primary)
        }
      } else if model.isRoot {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            model.onFilterButtonTapped()
          } label: {
            Label(
              filterButtonLabel ?? "All",
              systemImage: filterButtonLabel == nil
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
          }
          .tint(.primary)
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          ConfirmationButton(
            confirmation: .init(
              title: "Download All Books",
              message: "This will download all books in this collection. This may use significant storage space.",
              action: "Download All"
            ),
            action: model.onDownloadAllTapped
          ) {
            Label("Download All", systemImage: "arrow.down.circle")
          }
          .tint(.primary)
        }

        if #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle(
            isOn: Binding(
              get: { preferences.libraryDisplayMode == .card },
              set: { isOn in
                if isOn && preferences.libraryDisplayMode != .card {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("Grid View", systemImage: "square.grid.2x2")
          }

          Toggle(
            isOn: Binding(
              get: { preferences.libraryDisplayMode == .row },
              set: { isOn in
                if isOn && preferences.libraryDisplayMode != .row {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("List View", systemImage: "rectangle.grid.1x3")
          }

          if model.isSelecting {
            Divider()

            Button(action: model.onSelectAllTapped) {
              Label(
                model.selectedIDs.count == model.selectableCount ? "Unselect All" : "Select All",
                systemImage: model.selectedIDs.count == model.selectableCount
                  ? "circle" : "checkmark.circle"
              )
            }

            if !model.selectedIDs.isEmpty {
              Divider()

              if model.actions.contains(.addToCollection) {
                Button(action: { model.onAddSelectionTapped(mode: .collections) }) {
                  Label("Add to Collection", systemImage: "square.stack.3d.up")
                }
              }

              if model.actions.contains(.addToPlaylist) {
                Button(action: { model.onAddSelectionTapped(mode: .playlists) }) {
                  Label("Add to Playlist", systemImage: "music.note.list")
                }
              }
            }
          } else {
            if model.actions.contains(.addToPlaylist),
              !(model.isRoot && preferences.collapseSeriesInLibrary)
            {
              Divider()

              Button(action: { model.onSelectTapped() }) {
                Label("Select", systemImage: "checkmark.circle")
              }
            }

            if model.showCollapseSeries {
              Divider()

              Toggle(isOn: $preferences.collapseSeriesInLibrary) {
                Label("Collapse Series", systemImage: "rectangle.stack")
              }
              .onChange(of: preferences.collapseSeriesInLibrary) { _, _ in
                model.onCollapseSeriesToggled()
              }
            }
          }

          if !model.sortOptions.isEmpty {
            Divider()

            Menu("Sort By") {
              ForEach(model.sortOptions, id: \.self) { sortBy in
                if model.currentSort == sortBy {
                  Button(
                    sortBy.displayTitle,
                    systemImage: model.ascending ? "chevron.up" : "chevron.down",
                    action: { model.onSortOptionTapped(sortBy) }
                  )
                } else {
                  Button(sortBy.displayTitle, action: { model.onSortOptionTapped(sortBy) })
                }
              }
            }
          }

          if showsPlayAction || model.actions.contains(.resetProgress) || model.actions.contains(.markAsFinished) {
            Divider()
          }

          if showsPlayAction {
            Button(action: hasSelection ? model.onPlaySelectedTapped : model.onPlayAllTapped) {
              Label(hasSelection ? "Play Selected" : "Play All", systemImage: "play.fill")
            }
          }

          if model.actions.contains(.resetProgress) {
            Button(action: model.onResetAllProgressTapped) {
              Label(
                hasSelection ? "Reset Selected Progress" : "Reset All Progress",
                systemImage: "arrow.counterclockwise"
              )
            }
          }

          if model.actions.contains(.markAsFinished) {
            Button(action: model.onMarkAllFinishedTapped) {
              Label(
                hasSelection ? "Mark Selected as Finished" : "Mark All as Finished",
                systemImage: "checkmark.shield"
              )
            }
          }
        } label: {
          Image(systemName: "ellipsis")
        }
        .tint(.primary)
      }
    }
    .onAppear {
      model.onAppear()
    }
    .onChange(of: preferences.libraryFilter) { _, newFilter in
      guard model.isRoot else { return }
      model.onFilterPreferenceChanged(newFilter)
    }
  }

  var libraryView: some View {
    ScrollView {
      Group {
        if model.isRoot {
          LibraryView(
            items: model.items,
            displayMode: preferences.libraryDisplayMode == .card ? .grid : .list,
            hasMorePages: model.hasMorePages,
            pageLoadFailed: model.pageLoadFailed,
            onLoadMore: model.loadNextPageIfNeeded,
            isSelecting: model.isSelecting,
            selectedIDs: model.selectedIDs,
            onToggleSelection: model.onToggleSelection
          )
        } else {
          LibraryView(
            items: model.items,
            displayMode: preferences.libraryDisplayMode == .card ? .grid : .list,
            hasMorePages: model.hasMorePages,
            pageLoadFailed: model.pageLoadFailed,
            onLoadMore: model.loadNextPageIfNeeded,
            isSelecting: model.isSelecting,
            selectedIDs: model.selectedIDs,
            onToggleSelection: model.onToggleSelection
          )
          .searchable(
            text: $model.search.searchText,
            prompt: "Filter books"
          )
          .onChange(of: model.search.searchText) { _, newValue in
            model.onSearchChanged(newValue)
          }
        }
      }
      .padding(.horizontal)
      .environment(\.itemDisplayMode, preferences.libraryDisplayMode)
    }
  }

  var hasSelection: Bool {
    model.isSelecting && !model.selectedIDs.isEmpty
  }

  var showsPlayAction: Bool {
    model.actions.contains(.playAll) && !model.items.isEmpty && (!model.isSelecting || hasSelection)
  }

  var selectionTitle: String {
    if model.selectedIDs.isEmpty {
      String(localized: "Select Items")
    } else {
      String(localized: "\(model.selectedIDs.count) Selected")
    }
  }

  var filterButtonLabel: String? {
    switch model.filters?.selectedFilter {
    case .all: return nil
    case .explicit: return "Explicit"
    case .abridged: return "Abridged"
    case .progress(let name): return name
    case .authors(_, let name): return name
    case .series(_, let name): return name
    case .narrators(let name): return name
    case .genres(let name): return name
    case .tags(let name): return name
    case .languages(let name): return name
    case .publishers(let name): return name
    case .publishedDecades(let decade): return decade
    case nil: return nil
    }
  }
}

extension LibraryPage {
  @Observable
  class Model: ObservableObject {
    struct Actions: OptionSet {
      let rawValue: Int

      static let markAsFinished = Actions(rawValue: 1 << 0)
      static let resetProgress = Actions(rawValue: 1 << 1)
      static let addToPlaylist = Actions(rawValue: 1 << 2)
      static let addToCollection = Actions(rawValue: 1 << 3)
      static let playAll = Actions(rawValue: 1 << 4)
    }

    var isLoading: Bool
    var hasMorePages: Bool
    var pageLoadFailed: Bool = false

    var isRoot: Bool

    var sortOptions: [SortBy]
    var currentSort: SortBy?
    var ascending: Bool = true

    var title: String

    var items: [LibraryView.Item]
    var search: SearchView.Model

    var showCollapseSeries: Bool
    var actions: Actions = []

    var filters: FilterPicker.Model?
    var showingFilterSelection: Bool = false

    var isSelecting: Bool = false
    var selectedIDs: [String] = []
    var collectionSelector: CollectionSelectorSheet.Model?

    var selectableCount: Int {
      items.count { if case .book = $0 { true } else { false } }
    }

    func onAppear() {}
    func refresh() async {}
    func onSortOptionTapped(_ sortBy: SortBy) {}
    func onSearchChanged(_ searchText: String) {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}
    func onCollapseSeriesToggled() {}
    func onDownloadAllTapped() {}
    func onPlayAllTapped() {}
    func onPlaySelectedTapped() {}
    func onResetAllProgressTapped() {}
    func onMarkAllFinishedTapped() {}
    func onFilterButtonTapped() {}
    func onFilterPreferenceChanged(_ filter: LibraryPageModel.Filter) {}
    func onSelectTapped() {}
    func onCancelSelectTapped() {}
    func onSelectAllTapped() {}
    func onToggleSelection(_ id: String) {}
    func onAddSelectionTapped(mode: CollectionMode) {}

    init(
      isLoading: Bool = true,
      hasMorePages: Bool = false,
      isRoot: Bool = true,
      sortOptions: [SortBy] = [],
      currentSort: SortBy? = nil,
      showCollapseSeries: Bool = false,
      items: [LibraryView.Item] = [],
      search: SearchView.Model = SearchView.Model(),
      filters: FilterPicker.Model? = nil,
      title: String = "Library"
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.isRoot = isRoot
      self.sortOptions = sortOptions
      self.showCollapseSeries = showCollapseSeries
      self.currentSort = currentSort
      self.items = items
      self.search = search
      self.filters = filters
      self.title = title
    }
  }
}

extension LibraryPage.Model: Hashable {
  static func == (lhs: LibraryPage.Model, rhs: LibraryPage.Model) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension LibraryPage.Model {
  static var mock: LibraryPage.Model {
    let sampleItems: [LibraryView.Item] = [
      .book(
        BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
        )
      ),
      .book(
        BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
        )
      ),
      .series(SeriesCard.Model.mock),
      .book(
        BookCard.Model(
          title: "Foundation",
          details: "Isaac Asimov",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
        )
      ),
    ]

    return LibraryPage.Model(items: sampleItems)
  }
}

extension SortBy {
  var displayTitle: LocalizedStringResource {
    switch self {
    case .title: "Title"
    case .authorName: "Author Name"
    case .authorNameLF: "Author (Last, First)"
    case .author: "Author"
    case .publishedYear: "Published Year"
    case .addedAt: "Date Added"
    case .size: "File Size"
    case .duration: "Duration"
    case .numEpisodes: "# of Episodes"
    case .updatedAt: "Last Updated"
    case .progress: "Progress: Last Update"
    case .progressFinishedAt: "Progress: Finished"
    case .progressCreatedAt: "Progress: Started"
    case .birthtime: "File Birthtime"
    case .modified: "File Modified"
    case .random: "Randomly"
    }
  }
}

#Preview("LibraryPage - Loading") {
  LibraryPage(model: .init(isLoading: true))
}

#Preview("LibraryPage - Empty") {
  LibraryPage(model: .init())
}

#Preview("LibraryPage - With Books") {
  LibraryPage(model: .mock)
}
