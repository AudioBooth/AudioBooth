import API
import Combine
import NukeUI
import SwiftUI

struct AuthorsPage: View {
  @ObservedObject private var preferences = UserPreferences.shared
  @ObservedObject var model: Model

  @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 40

  var body: some View {
    content
      .navigationTitle("Authors")
      .refreshable {
        await model.refresh()
      }
      .conditionalSearchable(
        text: $model.searchViewModel.searchText,
        prompt: "Search books, series, and authors"
      )
      .toolbar { toolbarContent }
      .onAppear(perform: model.onAppear)
  }

  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    if #available(iOS 26.0, *) {
      ToolbarItem(placement: .topBarLeading) {
        Color.clear
      }
      .sharedBackgroundVisibility(.hidden)
    }

    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        ForEach(AuthorsService.SortBy.allCases, id: \.self) { sortBy in
          if preferences.authorsSortBy == sortBy {
            Button(
              sortBy.displayTitle,
              systemImage: preferences.authorsSortAscending ? "chevron.up" : "chevron.down"
            ) {
              model.onSortOptionTapped(sortBy)
            }
          } else {
            Button(sortBy.displayTitle) {
              model.onSortOptionTapped(sortBy)
            }
          }
        }
      } label: {
        Image(systemName: "arrow.up.arrow.down")
          .foregroundColor(.primary)
      }
    }
  }

  @ViewBuilder
  var content: some View {
    if !model.searchViewModel.searchText.isEmpty {
      SearchView(model: model.searchViewModel)
    } else if model.isLoading && model.sections.isEmpty {
      ProgressView("Loading authors...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.sections.isEmpty && !model.isLoading {
      ContentUnavailableView(
        "No Authors Found",
        systemImage: "person.2",
        description: Text("Your library appears to have no authors or no library is selected.")
      )
    } else {
      authorsRowContent
    }
  }

  var authorsRowContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        authorsList
      }
      .overlay(alignment: .trailing) {
        if [.name, .lastFirst].contains(preferences.authorsSortBy) {
          AlphabetScrollBar(
            onLetterTapped: { model.onLetterTapped($0) },
            reversed: !preferences.authorsSortAscending
          )
        }
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
      ForEach(model.sections) { section in
        Section {
          ForEach(section.authors, id: \.id) { author in
            authorRow(for: author)
          }
        } header: {
          if !section.letter.isEmpty {
            sectionHeader(for: section.letter)
          }
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
            .frame(width: avatarSize, height: avatarSize)
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
      .frame(width: avatarSize, height: avatarSize)
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

    var sections: [AuthorSection]
    var searchViewModel: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}
    func loadNextPageIfNeeded() {}
    func onLetterTapped(_ letter: String) {}
    func onSortOptionTapped(_ sortBy: AuthorsService.SortBy) {}

    init(
      isLoading: Bool = false,
      hasMorePages: Bool = false,
      sections: [AuthorSection] = []
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.sections = sections
    }
  }
}

extension AuthorsService.SortBy {
  var displayTitle: String {
    switch self {
    case .name: "First Last"
    case .lastFirst: "Last First"
    case .numBooks: "# of Books"
    case .addedAt: "Date Added"
    case .updatedAt: "Last Updated"
    }
  }
}

extension AuthorsPage.Model {
  static var mock: AuthorsPage.Model {
    let sections: [AuthorsPage.AuthorSection] = [
      AuthorsPage.AuthorSection(
        id: "A",
        letter: "A",
        authors: [
          AuthorCard.Model(
            name: "Andrew Seipe",
            bookCount: 15,
            imageURL: URL(
              string:
                "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
            )
          )
        ]
      ),
      AuthorsPage.AuthorSection(
        id: "B",
        letter: "B",
        authors: [
          AuthorCard.Model(
            name: "Brandon Sanderson",
            bookCount: 15,
            imageURL: URL(
              string:
                "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
            )
          )
        ]
      ),
      AuthorsPage.AuthorSection(
        id: "T",
        letter: "T",
        authors: [
          AuthorCard.Model(
            name: "Terry Pratchett",
            bookCount: 8,
            imageURL: URL(
              string:
                "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Terry_Pratchett_cropped.jpg/220px-Terry_Pratchett_cropped.jpg"
            )
          )
        ]
      ),
    ]

    return AuthorsPage.Model(sections: sections)
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
