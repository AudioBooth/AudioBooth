import Combine
import SwiftUI

struct PlaylistSelectorSheet: View {
  @Environment(\.dismiss) var dismiss

  @ObservedObject var model: Model
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if model.isLoading && model.playlists.isEmpty {
          ProgressView("Loading playlists...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.playlists.isEmpty && !model.isLoading {
          VStack(spacing: 16) {
            ContentUnavailableView(
              "You have no playlists",
              systemImage: "music.note.list",
              description: Text("Create your first playlist below.")
            )

            Text("Playlists are private. Only the user who creates them can see them.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            ForEach(model.playlists) { playlist in
              HStack(spacing: 12) {
                PlaylistRow(model: playlist)

                if model.containsBook(playlist) {
                  Button(action: {
                    model.onRemoveFromPlaylist(playlist)
                  }) {
                    Image(systemName: "minus.circle.fill")
                      .foregroundStyle(.red)
                      .font(.title2)
                  }
                  .buttonStyle(.plain)
                } else {
                  Button(action: {
                    model.onAddToPlaylist(playlist)
                  }) {
                    Image(systemName: "plus.circle")
                      .foregroundStyle(.blue)
                      .font(.title2)
                  }
                  .buttonStyle(.plain)
                }
              }
              .contentShape(Rectangle())
            }
          }
        }

        Divider()

        HStack(spacing: 12) {
          TextField("New playlist name", text: $model.newPlaylistName)
            .textFieldStyle(.roundedBorder)
            .focused($isTextFieldFocused)
            .submitLabel(.done)
            .onSubmit {
              model.onCreatePlaylist()
            }

          Button(action: {
            model.onCreatePlaylist()
          }) {
            Text("Create")
              .fontWeight(.semibold)
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
      }
      .navigationTitle("Add to Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .playlist(let id):
          PlaylistDetailPage(model: PlaylistDetailPageModel(playlistID: id))
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .series, .author, .narrator, .genre, .tag, .offline:
          EmptyView()
        }
      }
      .onAppear {
        model.onAppear()
      }
    }
  }
}

extension PlaylistSelectorSheet {
  @Observable
  class Model: ObservableObject {
    var isPresented: Bool
    var isLoading: Bool
    var playlists: [PlaylistRow.Model]
    var playlistsContainingBook: Set<String>
    var newPlaylistName: String

    func onAppear() {}
    func onAddToPlaylist(_ playlist: PlaylistRow.Model) {}
    func onRemoveFromPlaylist(_ playlist: PlaylistRow.Model) {}
    func onCreatePlaylist() {}

    func containsBook(_ playlist: PlaylistRow.Model) -> Bool {
      playlistsContainingBook.contains(playlist.id)
    }

    init(
      isPresented: Bool = true,
      isLoading: Bool = false,
      playlists: [PlaylistRow.Model] = [],
      playlistsContainingBook: Set<String> = [],
      newPlaylistName: String = ""
    ) {
      self.isPresented = isPresented
      self.isLoading = isLoading
      self.playlists = playlists
      self.playlistsContainingBook = playlistsContainingBook
      self.newPlaylistName = newPlaylistName
    }
  }
}

extension PlaylistSelectorSheet.Model {
  static var mock: PlaylistSelectorSheet.Model {
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

    return PlaylistSelectorSheet.Model(
      playlists: samplePlaylists,
      playlistsContainingBook: ["1"]
    )
  }
}

#Preview("PlaylistSelectorSheet - Loading") {
  PlaylistSelectorSheet(model: .init(isLoading: true))
}

#Preview("PlaylistSelectorSheet - Empty") {
  PlaylistSelectorSheet(model: .init())
}

#Preview("PlaylistSelectorSheet - With Playlists") {
  PlaylistSelectorSheet(model: .mock)
}
