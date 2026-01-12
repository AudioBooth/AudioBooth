import API
import SwiftUI

struct LibraryRootPage: View {
  enum LibraryType: Hashable {
    case library
    case authors
    case narrators
  }

  @State private var selectedType: LibraryType = .library
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  var body: some View {
    NavigationStack {
      VStack {
        switch selectedType {
        case .library:
          LibraryPage(model: LibraryPageModel())
            .id(libraries.current?.id)
        case .authors:
          AuthorsPage(model: AuthorsPageModel())
            .id(libraries.current?.id)
        case .narrators:
          NarratorsPage(model: NarratorsPageModel())
            .id(libraries.current?.id)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Library Type", selection: $selectedType) {
            Text("Library").tag(LibraryType.library)
            Text("Authors").tag(LibraryType.authors)
            Text("Narrators").tag(LibraryType.narrators)
          }
          .pickerStyle(.segmented)
          .controlSize(.large)
          .font(.subheadline)
          .tint(.primary)
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .offline:
          OfflineListView(model: OfflineListViewModel())
        case .author(let id, let name):
          AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name))
        case .series, .narrator, .genre, .tag:
          LibraryPage(model: LibraryPageModel(destination: destination))
        case .playlist, .collection, .stats:
          EmptyView()
        }
      }
    }
  }
}
