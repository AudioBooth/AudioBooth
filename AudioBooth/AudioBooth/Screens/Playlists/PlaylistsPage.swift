import Combine
import SwiftUI

struct PlaylistsPage: View {
  @StateObject var model: Model

  var body: some View {
    Group {
      if model.isLoading && model.playlists.isEmpty {
        ProgressView("Loading playlists...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.playlists.isEmpty && !model.isLoading {
        ContentUnavailableView(
          "No Playlists",
          systemImage: "music.note.list",
          description: Text("Create your first playlist to get started.")
        )
      } else {
        List {
          ForEach(model.playlists) { playlist in
            NavigationLink(value: NavigationDestination.playlist(id: playlist.id)) {
              PlaylistRow(model: playlist)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
          }
          .onDelete { indexSet in
            model.onDelete(at: indexSet)
          }

          if model.hasMorePages {
            ProgressView()
              .frame(maxWidth: .infinity)
              .onAppear {
                model.loadNextPageIfNeeded()
              }
          }
        }
        .listStyle(.plain)
      }
    }
    .refreshable {
      await model.refresh()
    }
    .onAppear {
      model.onAppear()
    }
  }
}

extension PlaylistsPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var playlists: [PlaylistRow.Model]
    var hasMorePages: Bool

    func onAppear() {}
    func refresh() async {}
    func onDelete(at indexSet: IndexSet) {}
    func loadNextPageIfNeeded() {}

    init(
      isLoading: Bool = false,
      playlists: [PlaylistRow.Model] = [],
      hasMorePages: Bool = false
    ) {
      self.isLoading = isLoading
      self.playlists = playlists
      self.hasMorePages = hasMorePages
    }
  }
}

extension PlaylistsPage.Model: Hashable {
  static func == (lhs: PlaylistsPage.Model, rhs: PlaylistsPage.Model) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension PlaylistsPage.Model {
  static var mock: PlaylistsPage.Model {
    let samplePlaylists: [PlaylistRow.Model] = [
      PlaylistRow.Model(
        id: "1",
        name: "My Favorites",
        description: "My favorite audiobooks",
        count: 5,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
        ]
      ),
      PlaylistRow.Model(
        id: "2",
        name: "Science Fiction",
        description: nil,
        count: 12,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
        ]
      ),
      PlaylistRow.Model(
        id: "3",
        name: "Currently Reading",
        description: "Books I'm actively listening to",
        count: 3,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!
        ]
      ),
    ]

    return PlaylistsPage.Model(playlists: samplePlaylists)
  }
}

#Preview("PlaylistsPage - Loading") {
  NavigationStack {
    PlaylistsPage(model: .init(isLoading: true))
  }
}

#Preview("PlaylistsPage - Empty") {
  NavigationStack {
    PlaylistsPage(model: .init())
  }
}

#Preview("PlaylistsPage - With Playlists") {
  NavigationStack {
    PlaylistsPage(model: .mock)
  }
}
