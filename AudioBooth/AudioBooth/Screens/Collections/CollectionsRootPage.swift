import SwiftUI

struct CollectionsRootPage: View {
  enum CollectionType: Hashable {
    case series
    case collections
    case playlists
  }

  @State private var selectedType: CollectionType = .series

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
        case .series, .author, .narrator, .genre, .tag, .offline:
          LibraryPage(model: LibraryPageModel(destination: destination))
        }
      }
    }
  }
}

#Preview {
  CollectionsRootPage()
}
