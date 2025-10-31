import Combine
import SwiftUI

struct AuthorsPage: View {
  @StateObject var model: Model

  var body: some View {
    NavigationStack {
      content
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .book(let id):
            BookDetailsView(model: BookDetailsViewModel(bookID: id))
          case .series, .author, .narrator, .genre, .tag, .offline:
            LibraryPage(model: LibraryPageModel(destination: destination))
          }
        }
    }
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
              "Your library appears to have no authors or no library is selected.")
          )
        } else {
          authorsContent
        }
      }
    }
    .navigationTitle("Authors")
    .refreshable {
      await model.refresh()
    }
    .conditionalSearchable(
      text: $model.searchViewModel.searchText, prompt: "Search books, series, and authors"
    )
    .onAppear(perform: model.onAppear)
  }

  var authorsContent: some View {
    ScrollView {
      LazyVStack {
        AuthorsView(authors: model.authors)
          .padding(.horizontal)

        if let authorsModel = model as? AuthorsPageModel {
          Color.clear
            .frame(height: 1)
            .onAppear {
              Task {
                await authorsModel.loadNextPageIfNeeded()
              }
            }
        }
      }
    }
  }
}

extension AuthorsPage {
  @Observable class Model: ObservableObject {
    var isLoading: Bool

    var authors: [AuthorCard.Model]
    var searchViewModel: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}

    init(
      isLoading: Bool = false,
      authors: [AuthorCard.Model] = []
    ) {
      self.isLoading = isLoading
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
