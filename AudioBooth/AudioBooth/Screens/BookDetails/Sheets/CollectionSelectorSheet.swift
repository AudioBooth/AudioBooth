import Combine
import SwiftUI

struct CollectionSelectorSheet: View {
  @Environment(\.dismiss) var dismiss

  @ObservedObject var model: Model
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if model.isLoading && model.playlists.isEmpty {
          loadingView
        } else if model.playlists.isEmpty && !model.isLoading {
          emptyStateView
        } else {
          listView
        }

        if model.canEdit {
          createFieldView
        }
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Label("Close", systemImage: "xmark")
          }
          .tint(.primary)
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .playlist(let id):
          CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .series, .author, .narrator, .genre, .tag, .offline, .collection, .stats, .authorLibrary:
          EmptyView()
        }
      }
      .onAppear {
        model.onAppear()
      }
    }
  }

  private var navigationTitle: String {
    switch model.mode {
    case .playlists:
      return String(localized: "Add to Playlist")
    case .collections:
      return String(localized: "Collections")
    }
  }

  private var loadingMessage: String {
    switch model.mode {
    case .playlists:
      return String(localized: "Loading playlists...")
    case .collections:
      return String(localized: "Loading collections...")
    }
  }

  private var emptyStateTitle: String {
    switch model.mode {
    case .playlists:
      return String(localized: "You have no playlists")
    case .collections:
      return String(localized: "No collections")
    }
  }

  private var emptyStateIcon: String {
    switch model.mode {
    case .playlists:
      return "music.note.list"
    case .collections:
      return "square.stack.3d.up.fill"
    }
  }

  private var emptyStateMessage: String {
    switch model.mode {
    case .playlists:
      return String(localized: "Create your first playlist below.")
    case .collections:
      return model.canEdit
        ? String(localized: "Create your first collection below.")
        : String(localized: "No collections available.")
    }
  }

  private var createFieldPlaceholder: String {
    switch model.mode {
    case .playlists:
      return String(localized: "New playlist name")
    case .collections:
      return String(localized: "New collection name")
    }
  }

  private var loadingView: some View {
    ProgressView(loadingMessage)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      ContentUnavailableView(
        emptyStateTitle,
        systemImage: emptyStateIcon,
        description: Text(emptyStateMessage)
      )

      switch model.mode {
      case .playlists:
        Text("Playlists are private. Only the user who creates them can see them.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      case .collections:
        if model.canEdit {
          Text("Collections are shared across all users on the server.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var listView: some View {
    List {
      ForEach(model.playlists) { playlist in
        HStack(spacing: 12) {
          CollectionRow(model: playlist)

          if model.canEdit {
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
                  .foregroundStyle(Color.accentColor)
                  .font(.title2)
              }
              .buttonStyle(.plain)
            }
          } else {
            if model.containsBook(playlist) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            }
          }
        }
        .contentShape(Rectangle())
      }
    }
  }

  private var createFieldView: some View {
    VStack(spacing: 0) {
      Divider()

      HStack(spacing: 12) {
        TextField(createFieldPlaceholder, text: $model.newPlaylistName)
          .textFieldStyle(.roundedBorder)
          .focused($isTextFieldFocused)
          .submitLabel(.done)
          .onSubmit {
            model.onCreateCollection()
          }

        Button(action: {
          model.onCreateCollection()
        }) {
          Text("Create")
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding()
    }
  }
}

extension CollectionSelectorSheet {
  @Observable
  class Model: ObservableObject {
    var isPresented: Bool
    var isLoading: Bool
    var playlists: [CollectionRow.Model]
    var playlistsContainingBook: Set<String>
    var newPlaylistName: String
    var mode: CollectionMode
    var canEdit: Bool

    func onAppear() {}
    func onAddToPlaylist(_ playlist: CollectionRow.Model) {}
    func onRemoveFromPlaylist(_ playlist: CollectionRow.Model) {}
    func onCreateCollection() {}

    func containsBook(_ playlist: CollectionRow.Model) -> Bool {
      playlistsContainingBook.contains(playlist.id)
    }

    init(
      isPresented: Bool = true,
      isLoading: Bool = false,
      playlists: [CollectionRow.Model] = [],
      playlistsContainingBook: Set<String> = [],
      newPlaylistName: String = "",
      mode: CollectionMode = .playlists,
      canEdit: Bool = true
    ) {
      self.isPresented = isPresented
      self.isLoading = isLoading
      self.playlists = playlists
      self.playlistsContainingBook = playlistsContainingBook
      self.newPlaylistName = newPlaylistName
      self.mode = mode
      self.canEdit = canEdit
    }
  }
}

extension CollectionSelectorSheet.Model {
  static var mock: CollectionSelectorSheet.Model {
    let samplePlaylists: [CollectionRow.Model] = [
      CollectionRow.Model(
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
      CollectionRow.Model(
        id: "2",
        name: "Science Fiction",
        description: nil,
        count: 12,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
        ]
      ),
      CollectionRow.Model(
        id: "3",
        name: "Currently Reading",
        description: "Books I'm actively listening to",
        count: 3,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!
        ]
      ),
    ]

    return CollectionSelectorSheet.Model(
      playlists: samplePlaylists,
      playlistsContainingBook: ["1"]
    )
  }
}

#Preview("CollectionSelectorSheet - Loading") {
  CollectionSelectorSheet(model: .init(isLoading: true))
}

#Preview("CollectionSelectorSheet - Empty") {
  CollectionSelectorSheet(model: .init())
}

#Preview("CollectionSelectorSheet - With Playlists") {
  CollectionSelectorSheet(model: .mock)
}
