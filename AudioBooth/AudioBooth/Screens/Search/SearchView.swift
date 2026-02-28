import API
import Combine
import SwiftUI

struct SearchPage: View {
  @StateObject var model: SearchView.Model

  var body: some View {
    NavigationStack {
      SearchView(model: model)
        .searchable(text: $model.searchText)
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .book(let id):
            BookDetailsView(model: BookDetailsViewModel(bookID: id))
          case .author(let id, let name):
            AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name))
          case .series, .narrator, .genre, .tag, .offline, .authorLibrary:
            LibraryPage(model: LibraryPageModel(destination: destination))
          case .podcast(let id, let episodeID):
            PodcastDetailsView(model: PodcastDetailsViewModel(podcastID: id, episodeID: episodeID))
          case .playlist, .collection, .stats:
            EmptyView()
          }
        }
    }
  }
}

struct SearchView: View {
  @ObservedObject var model: Model
  var body: some View {
    ScrollView {
      content
    }
    .scrollDismissesKeyboard(.interactively)
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
        .containerRelativeFrame(.vertical)
    } else if model.isLoading {
      loadingState
        .containerRelativeFrame(.vertical)
    } else if model.books.isEmpty, model.series.isEmpty, model.authors.isEmpty,
      model.narrators.isEmpty, model.tags.isEmpty, model.genres.isEmpty
    {
      noResultsState
        .containerRelativeFrame(.vertical)
    } else {
      resultsContent
    }
  }

  var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text("Search for books, series, authors, narrators, tags, or genres")
        .font(.headline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
  }

  var loadingState: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)

      Text("Searching...")
        .font(.headline)
        .foregroundColor(.secondary)
    }
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
  }

  var resultsContent: some View {
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

      if !model.narrators.isEmpty {
        narratorsSection
      }

      if !model.tags.isEmpty {
        tagsSection
      }

      if !model.genres.isEmpty {
        genresSection
      }
    }
    .padding()
    .padding(.bottom, 50)
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

      LibraryView(items: model.books.map { .book($0) }, displayMode: .grid)
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
        .environment(\.itemDisplayMode, .card)
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

  var narratorsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Narrators")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.narrators.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      FlowLayout(spacing: 8) {
        ForEach(model.narrators, id: \.self) { narrator in
          NavigationLink(value: NavigationDestination.narrator(name: narrator)) {
            Chip(
              title: narrator,
              icon: "person.wave.2.fill",
              color: .blue,
              mode: .large
            )
          }
        }
      }
    }
  }

  var tagsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Tags")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.tags.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      FlowLayout(spacing: 8) {
        ForEach(model.tags, id: \.self) { tag in
          NavigationLink(value: NavigationDestination.tag(name: tag)) {
            Chip(
              title: tag,
              icon: "tag.fill",
              color: .gray,
              mode: .large
            )
          }
        }
      }
    }
  }

  var genresSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Genres")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Text("\(model.genres.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      FlowLayout(spacing: 8) {
        ForEach(model.genres, id: \.self) { genre in
          NavigationLink(value: NavigationDestination.genre(name: genre)) {
            Chip(
              title: genre,
              icon: "theatermasks.fill",
              color: .gray,
              mode: .large
            )
          }
        }
      }
    }
  }
}

extension SearchView {
  @Observable class Model: ObservableObject {
    var searchText: String = ""
    var isLoading: Bool = false
    var books: [BookCard.Model] = []
    var series: [SeriesCard.Model] = []
    var authors: [AuthorCard.Model] = []
    var narrators: [String] = []
    var tags: [String] = []
    var genres: [String] = []

    func onSearchChanged(_ searchText: String) {}
  }
}

extension SearchView.Model {
  static var mock: SearchView.Model {
    let model = SearchView.Model()
    model.books = [
      BookCard.Model(
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
      ),
      BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
      ),
      BookCard.Model(
        title: "The Foundation",
        details: "Isaac Asimov",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
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
