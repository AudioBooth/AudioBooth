import SwiftUI

struct LibraryRootPage: View {
  var body: some View {
    NavigationStack {
      LibraryPage(model: LibraryPageModel())
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
}
