import API
import SwiftUI

struct CollectionsRootPage: View {
  enum CollectionType: CaseIterable {
    case series
    case collections
    case playlists

    var next: CollectionType {
      let all = CollectionType.allCases
      let index = all.firstIndex(of: self) ?? 0
      return all[(index + 1) % all.count]
    }
  }

  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @Binding var selectedType: CollectionType

  var body: some View {
    NavigationStack {
      VStack {
        switch selectedType {
        case .series:
          SeriesPage(model: SeriesPageModel())
        case .collections:
          CollectionsPage(model: CollectionsPageModel(mode: .collections))
        case .playlists:
          CollectionsPage(model: CollectionsPageModel(mode: .playlists))
        }
      }
      .id(libraries.current?.id)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Collection Type", selection: $selectedType) {
            Text("Series").tag(CollectionType.series)
            Text("Collections").tag(CollectionType.collections)
            Text("Playlists").tag(CollectionType.playlists)
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
        case .playlist(let id):
          CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
        case .collection(let id):
          CollectionDetailPage(
            model: CollectionDetailPageModel(collectionID: id, mode: .collections)
          )
        case .author(let id, let name):
          AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name))
        case .series, .narrator, .genre, .tag, .offline:
          LibraryPage(model: LibraryPageModel(destination: destination))

        case .stats:
          EmptyView()
        }
      }
    }
  }
}

#Preview {
  CollectionsRootPage(selectedType: .constant(.series))
}
