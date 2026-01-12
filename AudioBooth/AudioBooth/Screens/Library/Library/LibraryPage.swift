import API
import Combine
import SwiftUI

struct LibraryPage: View {
  @StateObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

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
        if model.isLoading && model.books.isEmpty {
          ProgressView("Loading books...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.books.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "magnifyingglass",
            description: Text("No books match your search.")
          )
        } else if model.books.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Books Found",
            systemImage: "books.vertical",
            description: Text("Your library appears to be empty or no library is selected.")
          )
        } else {
          ScrollView {
            LibraryView(
              books: model.books,
              displayMode: preferences.libraryDisplayMode == .card ? .grid : .list,
              hasMorePages: model.hasMorePages,
              onLoadMore: model.loadNextPageIfNeeded
            )
            .environment(\.bookCardDisplayMode, preferences.libraryDisplayMode)
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
        ToolbarItem(placement: .navigationBarTrailing) {
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

        if #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
        }
      } else {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            model.onDownloadAllTapped()
          } label: {
            Label("Download All", systemImage: "arrow.down.circle")
          }
          .tint(.primary)
        }
      }

      ToolbarItem(placement: .navigationBarTrailing) {
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
            Label("List View", systemImage: "list.bullet")
          }

          if model.isRoot {
            Divider()

            Toggle(isOn: $preferences.collapseSeriesInLibrary) {
              Label("Collapse Series", systemImage: "rectangle.stack")
            }
            .onChange(of: preferences.collapseSeriesInLibrary) { _, _ in
              model.onCollapseSeriesToggled()
            }
          }

          if model.sortBy != nil {
            Divider()

            Menu("Sort By") {
              sortByOption(.title)
              sortByOption(.authorName)
              sortByOption(.authorNameLF)
              sortByOption(.publishedYear)
              sortByOption(.addedAt)
              sortByOption(.size)
              sortByOption(.duration)
              sortByOption(.updatedAt)
              sortByOption(.progress)
              sortByOption(.progressFinishedAt)
              sortByOption(.progressCreatedAt)
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
  }

  @ViewBuilder
  private func sortByOption(_ sortBy: BooksService.SortBy) -> some View {
    let title: String =
      switch sortBy {
      case .title: "Title"
      case .authorName: "Author Name"
      case .authorNameLF: "Author (Last, First)"
      case .publishedYear: "Published Year"
      case .addedAt: "Date Added"
      case .size: "File Size"
      case .duration: "Duration"
      case .updatedAt: "Last Updated"
      case .progress: "Progress: Last Update"
      case .progressFinishedAt: "Progress: Finished"
      case .progressCreatedAt: "Progress: Started"
      }

    if let current = model.sortBy, current == sortBy {
      Button(
        title,
        systemImage: model.ascending ? "chevron.up" : "chevron.down",
        action: { model.onSortByTapped(sortBy) }
      )
    } else {
      Button(title, action: { model.onSortByTapped(sortBy) })
    }
  }

  var filterButtonLabel: String? {
    guard let filters = model.filters else { return nil }

    switch filters.selectedFilter {
    case .all: return nil
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

    var sortBy: BooksService.SortBy?
    var ascending: Bool = true

    var title: String

    var books: [BookCard.Model]
    var search: SearchView.Model

    var filters: FilterPicker.Model?
    var showingFilterSelection: Bool = false

    func onAppear() {}
    func refresh() async {}
    func onSortByTapped(_ sortBy: BooksService.SortBy) {}
    func onSearchChanged(_ searchText: String) {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}
    func onCollapseSeriesToggled() {}
    func onDownloadAllTapped() {}
    func onFilterButtonTapped() {}

    init(
      isLoading: Bool = true,
      hasMorePages: Bool = false,
      isRoot: Bool = true,
      sortBy: BooksService.SortBy? = .title,
      books: [BookCard.Model] = [],
      search: SearchView.Model = SearchView.Model(),
      filters: FilterPicker.Model? = nil,
      title: String = "Library"
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.isRoot = isRoot
      self.sortBy = sortBy
      self.books = books
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
    let sampleBooks: [BookCard.Model] = [
      BookCard.Model(
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
      ),
      BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
      ),
      BookCard.Model(
        title: "The Foundation",
        details: "Isaac Asimov",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")
      ),
    ]

    return LibraryPage.Model(books: sampleBooks)
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
