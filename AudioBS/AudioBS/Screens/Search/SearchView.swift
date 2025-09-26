import Audiobookshelf
import SwiftUI

struct SearchPage: View {
  @StateModel var model: SearchView.Model

  init(model: SearchView.Model? = nil) {
    if let model {
      self._model = StateModel(wrappedValue: model)
    } else {
      self._model = StateModel(mock: .mock, default: SearchViewModel())
    }
  }

  var body: some View {
    SearchView(model: model)
      .searchable(text: $model.searchText)
  }
}

struct SearchView: View {
  @StateModel var model: Model

  init(model: Model? = nil) {
    if let model {
      self._model = StateModel(wrappedValue: model)
    } else {
      self._model = StateModel(mock: .mock, default: SearchViewModel())
    }
  }

  var body: some View {
    content
      .onAppear {
        model.onSearchChanged(model.searchText)
      }
      .onChange(of: model.searchText) { _, newValue in
        model.onSearchChanged(newValue)
      }
  }

  @ViewBuilder
  var content: some View {
    if model.searchText.isEmpty {
      emptyState
    } else if model.isLoading {
      loadingState
    } else if model.books.isEmpty && model.series.isEmpty && model.authors.isEmpty {
      noResultsState
    } else {
      resultsView
    }
  }

  var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text("Search for books, series, and authors")
        .font(.headline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var loadingState: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)

      Text("Searching...")
        .font(.headline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var noResultsState: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(.primary)

      Text("No results found")
        .font(.headline)
        .foregroundColor(.primary)

      Text("Try adjusting your search terms")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  var resultsView: some View {
    ScrollView {
      LazyVStack(spacing: 24) {
        if !model.books.isEmpty {
          booksSection
        }

        if !model.series.isEmpty {
          seriesSection
        }

        if !model.authors.isEmpty {
          authorsSection
        }
      }
      .padding()
    }
  }

  var booksSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Books")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.books.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      LibraryView(books: model.books)
    }
  }

  var seriesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Series")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.series.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      SeriesView(series: model.series)
    }
  }

  var authorsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Authors")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.authors.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      AuthorsView(authors: model.authors)
    }
  }
}

extension SearchView {
  @Observable class Model {
    var searchText: String = ""
    var isLoading: Bool = false
    var books: [BookCard.Model] = []
    var series: [SeriesCard.Model] = []
    var authors: [AuthorCard.Model] = []

    @MainActor func onSearchChanged(_ searchText: String) {}
  }
}

extension SearchView.Model {
  static var mock: SearchView.Model {
    let model = SearchView.Model()
    model.books = [
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
    model.series = [.mock, .mock]
    model.authors = [.mock, .mock]
    model.searchText = "sample search"
    return model
  }
}

#Preview("SearchView - Empty") {
  SearchView(model: SearchView.Model())
}

#Preview("SearchView - With Results") {
  SearchView(model: .mock)
}
