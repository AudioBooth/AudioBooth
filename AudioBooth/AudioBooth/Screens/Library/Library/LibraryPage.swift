import API
import Combine
import SwiftUI

struct LibraryPage: View {
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
        .searchable(
          text: $model.search.searchText,
          prompt: "Filter books"
        )
        .onChange(of: model.search.searchText) { _, newValue in
          model.onSearchChanged(newValue)
        }
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
        } else if model.items.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "magnifyingglass",
            description: Text("No books match your search.")
          )
        } else if model.items.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "books.vertical",
            description: Text("Your library appears to be empty or no library is selected.")
          )
        } else {
          ScrollView {
            LibraryView(
              items: model.items,
              displayMode: preferences.libraryDisplayMode == .card ? .grid : .list,
              hasMorePages: model.hasMorePages,
              onLoadMore: model.loadNextPageIfNeeded
            )
            .environment(\.itemDisplayMode, preferences.libraryDisplayMode)
            .padding(.horizontal)
          }
        }
      }
    }
    .navigationTitle(model.title)
    .sheet(isPresented: $model.showingFilterSelection) {
      if let filters = model.filters {
        NavigationStack {
          FilterPicker(model: filters)
        }
      }
    }
    .toolbar {
      if model.isRoot {
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

          if model.showCollapseSeries {
            Divider()

            Toggle(isOn: $preferences.collapseSeriesInLibrary) {
              Label("Collapse Series", systemImage: "rectangle.stack")
            }
            .onChange(of: preferences.collapseSeriesInLibrary) { _, _ in
              model.onCollapseSeriesToggled()
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

  var filterButtonLabel: String? {
    guard let filters = model.filters else { return nil }

    switch filters.selectedFilter {
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
    var isLoading: Bool
    var hasMorePages: Bool

    var isRoot: Bool

    var sortOptions: [SortBy]
    var currentSort: SortBy?
    var ascending: Bool = true

    var title: String

    var items: [LibraryView.Item]
    var search: SearchView.Model

    var showCollapseSeries: Bool

    var filters: FilterPicker.Model?
    var showingFilterSelection: Bool = false

    func onAppear() {}
    func refresh() async {}
    func onSortOptionTapped(_ sortBy: SortBy) {}
    func onSearchChanged(_ searchText: String) {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}
    func onCollapseSeriesToggled() {}
    func onDownloadAllTapped() {}
    func onFilterButtonTapped() {}
    func onFilterPreferenceChanged(_ filter: LibraryPageModel.Filter) {}

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
          title: "The Foundation",
          details: "Isaac Asimov",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
        )
      ),
    ]

    return LibraryPage.Model(items: sampleItems)
  }
}

extension SortBy {
  var displayTitle: String {
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
