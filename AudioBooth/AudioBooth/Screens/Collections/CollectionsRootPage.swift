import SwiftUI

struct CollectionsRootPage: View {
  enum CollectionType: Hashable {
    case series
    case playlists
  }

  @State private var selectedType: CollectionType = .series

  var body: some View {
    NavigationStack {
      Group {
        switch selectedType {
        case .series:
          SeriesPage(model: SeriesPageModel())
        case .playlists:
          PlaylistsPage(model: PlaylistsPageModel())
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Collection Type", selection: $selectedType) {
            Text("Series").tag(CollectionType.series)
            Text("Playlists").tag(CollectionType.playlists)
          }
          .pickerStyle(.segmented)
          .font(.subheadline)
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .playlist(let id):
          PlaylistDetailPage(model: PlaylistDetailPageModel(playlistID: id))
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
