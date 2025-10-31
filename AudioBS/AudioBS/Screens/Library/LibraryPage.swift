import API
import Combine
import SwiftUI

struct LibraryPage: View {
  @StateObject var model: Model

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
            LazyVStack {
              LibraryView(
                books: model.books,
                displayMode: model.displayMode == .card ? .grid : .list
              )
              .environment(\.bookCardDisplayMode, model.displayMode)
              .padding(.horizontal)

              Color.clear
                .frame(height: 1)
                .onAppear {
                  Task {
                    model.loadNextPageIfNeeded()
                  }
                }
            }
          }
        }
      }
    }
    .navigationTitle(model.title)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { model.onDisplayModeTapped() }) {
          Image(systemName: model.displayMode == .card ? "square.grid.2x2" : "list.bullet")
        }
      }

      if model.sortBy != nil {
        ToolbarItem(placement: .navigationBarTrailing) {
          Menu("", systemImage: "arrow.up.arrow.down") {
            sortByOption(.title)
            sortByOption(.authorName)
            sortByOption(.authorNameLF)
            sortByOption(.publishedYear)
            sortByOption(.addedAt)
            sortByOption(.size)
            sortByOption(.duration)
            sortByOption(.updatedAt)
          }
        }
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
}

extension LibraryPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool

    var isRoot: Bool

    var sortBy: BooksService.SortBy?
    var ascending: Bool = true

    @ObservationIgnored
    @AppStorage("libraryDisplayMode") var displayMode: BookCard.DisplayMode = .card

    var title: String

    var books: [BookCard.Model]
    var search: SearchView.Model

    func onAppear() {}
    func refresh() async {}
    func onSortByTapped(_ sortBy: BooksService.SortBy) {}
    func onSearchChanged(_ searchText: String) {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}

    init(
      isLoading: Bool = false,
      isRoot: Bool = true,
      sortBy: BooksService.SortBy? = .title,
      books: [BookCard.Model] = [],
      search: SearchView.Model = SearchView.Model(),
      title: String = "Library"
    ) {
      self.isLoading = isLoading
      self.isRoot = isRoot
      self.sortBy = sortBy
      self.books = books
      self.search = search
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
