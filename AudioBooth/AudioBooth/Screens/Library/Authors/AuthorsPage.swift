import Combine
import NukeUI
import SwiftUI

struct AuthorsPage: View {
  @AppStorage("authorsPageSortOrder") var sortOrder: SortOrder = .firstLast

  @ObservedObject var model: Model

  var body: some View {
    content
  }

  var content: some View {
    Group {
      if !model.searchViewModel.searchText.isEmpty {
        SearchView(model: model.searchViewModel)
      } else {
        if model.isLoading && model.authors.isEmpty {
          ProgressView("Loading authors...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.authors.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Authors Found",
            systemImage: "person.2",
            description: Text(
              "Your library appears to have no authors or no library is selected."
            )
          )
        } else {
          authorsRowContent
        }
      }
    }
    .navigationTitle("Authors")
    .refreshable {
      await model.refresh()
    }
    .conditionalSearchable(
      text: $model.searchViewModel.searchText,
      prompt: "Search books, series, and authors"
    )
    .toolbar {
      if #available(iOS 26.0, *) {
        ToolbarItem(placement: .topBarLeading) {
          Color.clear
        }
        .sharedBackgroundVisibility(.hidden)
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Sort Order", selection: $sortOrder) {
            Text("First Last").tag(SortOrder.firstLast)
            Text("Last First").tag(SortOrder.lastFirst)
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
            .foregroundColor(.primary)
        }
      }
    }
    .onAppear(perform: model.onAppear)
  }

  var authorSections: [AuthorSection] {
    let sortedAuthors = model.authors.sorted { lhs, rhs in
      switch sortOrder {
      case .firstLast:
        return lhs.name < rhs.name
      case .lastFirst:
        return lastNameFirst(lhs.name) < lastNameFirst(rhs.name)
      }
    }

    let grouped = Dictionary(grouping: sortedAuthors) { author in
      let name: String
      switch sortOrder {
      case .firstLast:
        name = author.name
      case .lastFirst:
        name = lastNameFirst(author.name)
      }
      return sectionLetter(for: name)
    }

    return grouped.map { letter, authors in
      AuthorSection(id: letter, letter: letter, authors: authors)
    }.sorted { lhs, rhs in
      if lhs.letter == "#" { return false }
      if rhs.letter == "#" { return true }
      return lhs.letter < rhs.letter
    }
  }

  private func sectionLetter(for name: String) -> String {
    guard let firstChar = name.uppercased().first else { return "#" }
    let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return validLetters.contains(firstChar) ? String(firstChar) : "#"
  }

  private func lastNameFirst(_ name: String) -> String {
    let components = name.components(separatedBy: " ")
    guard components.count > 1 else { return name }
    return components.last ?? name
  }

  var authorsRowContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        authorsList
      }
      .overlay(alignment: .trailing) {
        AlphabetScrollBar(
          onLetterTapped: { model.onLetterTapped($0) }
        )
      }
      .scrollIndicators(.hidden)
      .onChange(of: model.scrollTarget) { _, scrollTarget in
        guard let scrollTarget else { return }
        withAnimation(.easeOut(duration: 0.1)) {
          proxy.scrollTo(scrollTarget.target, anchor: .top)
        }
      }
    }
  }

  var authorsList: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(authorSections) { section in
        Section {
          ForEach(section.authors, id: \.id) { author in
            authorRow(for: author)
          }
        } header: {
          sectionHeader(for: section.letter)
        }
        .id(section.letter)
      }

      if model.hasMorePages {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
          .onAppear {
            model.loadNextPageIfNeeded()
          }
      }

      Color.clear
        .frame(height: 1)
        .id(Self.bottomScrollID)
    }
  }

  func authorRow(for author: AuthorCard.Model) -> some View {
    NavigationLink(value: NavigationDestination.author(id: author.id, name: author.name)) {
      HStack(spacing: 12) {
        authorImage(for: author)

        VStack(alignment: .leading, spacing: 2) {
          Text(author.name)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)

          if author.bookCount > 0 {
            Text("^[\(author.bookCount) book](inflect: true)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  func authorImage(for author: AuthorCard.Model) -> some View {
    if let imageURL = author.imageURL {
      LazyImage(url: imageURL) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
          placeholderImage
        }
      }
    } else {
      placeholderImage
    }
  }

  var placeholderImage: some View {
    Circle()
      .fill(Color.gray.opacity(0.3))
      .frame(width: 40, height: 40)
      .overlay(
        Image(systemName: "person.circle")
          .foregroundColor(.gray)
      )
  }

  func sectionHeader(for letter: String) -> some View {
    Text(letter)
      .font(.headline)
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(uiColor: .systemBackground))
  }
}

extension AuthorsPage {
  static let bottomScrollID = "BOTTOM"

  enum SortOrder: String {
    case firstLast = "First Last"
    case lastFirst = "Last First"
  }

  struct AuthorSection: Identifiable {
    let id: String
    let letter: String
    let authors: [AuthorCard.Model]
  }

  @Observable class Model: ObservableObject {
    var isLoading: Bool
    var hasMorePages: Bool
    var scrollTarget: ScrollTarget?

    struct ScrollTarget: Equatable {
      let id: UUID
      let target: String

      init(_ target: String) {
        self.id = UUID()
        self.target = target
      }
    }

    var authors: [AuthorCard.Model]
    var searchViewModel: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}
    func loadNextPageIfNeeded() {}
    func onLetterTapped(_ letter: String) {}

    init(
      isLoading: Bool = false,
      hasMorePages: Bool = false,
      authors: [AuthorCard.Model] = []
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.authors = authors
    }
  }
}

extension AuthorsPage.Model {
  static var mock: AuthorsPage.Model {
    let sampleAuthors: [AuthorCard.Model] = [
      AuthorCard.Model(
        name: "Andrew Seipe",
        bookCount: 15,
        imageURL: URL(
          string:
            "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
        )
      ),
      AuthorCard.Model(
        name: "Brandon Sanderson",
        bookCount: 15,
        imageURL: URL(
          string:
            "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
        )
      ),
      AuthorCard.Model(
        name: "Terry Pratchett",
        bookCount: 8,
        imageURL: URL(
          string:
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Terry_Pratchett_cropped.jpg/220px-Terry_Pratchett_cropped.jpg"
        )
      ),
    ]

    return AuthorsPage.Model(authors: sampleAuthors)
  }
}

#Preview("AuthorsPage - Loading") {
  AuthorsPage(model: .init(isLoading: true))
}

#Preview("AuthorsPage - Empty") {
  AuthorsPage(model: .init())
}

#Preview("AuthorsPage - With Authors") {
  AuthorsPage(model: .mock)
}
