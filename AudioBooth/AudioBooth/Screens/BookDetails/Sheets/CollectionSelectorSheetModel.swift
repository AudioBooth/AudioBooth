import API
import Foundation

final class CollectionSelectorSheetModel: CollectionSelectorSheet.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let bookID: String
  private let episodeID: String?

  init(bookID: String, episodeID: String? = nil, mode: CollectionMode = .playlists) {
    self.bookID = bookID
    self.episodeID = episodeID

    let canEdit: Bool
    switch mode {
    case .playlists:
      canEdit = true
    case .collections:
      canEdit = audiobookshelf.authentication.permissions?.update == true
    }

    super.init(mode: mode, canEdit: canEdit)
  }

  override func onAppear() {
    Task {
      await loadCollections()
    }
  }

  override func onAddToPlaylist(_ playlist: CollectionRow.Model) {
    Task {
      do {
        let updatedCollection: any CollectionLike

        switch mode {
        case .playlists:
          updatedCollection = try await audiobookshelf.playlists.addItems(
            playlistID: playlist.id,
            items: [bookID],
            episodeID: episodeID
          )
        case .collections:
          updatedCollection = try await audiobookshelf.collections.addItems(
            collectionID: playlist.id,
            items: [bookID]
          )
        }

        playlistsContainingBook.insert(playlist.id)
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          playlists[index] = CollectionRowModel(collection: updatedCollection)
        }
      } catch {
        print("Failed to add book: \(error)")
      }
    }
  }

  override func onRemoveFromPlaylist(_ playlist: CollectionRow.Model) {
    Task {
      do {
        let updatedCollection: any CollectionLike

        switch mode {
        case .playlists:
          updatedCollection = try await audiobookshelf.playlists.removeItem(
            playlistID: playlist.id,
            libraryItemID: bookID,
            episodeID: episodeID
          )
        case .collections:
          updatedCollection = try await audiobookshelf.collections.removeItem(
            collectionID: playlist.id,
            libraryItemID: bookID
          )
        }

        playlistsContainingBook.remove(playlist.id)

        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          if updatedCollection.itemCount == 0, mode == .playlists {
            playlists.remove(at: index)
          } else {
            playlists[index] = CollectionRowModel(collection: updatedCollection)
          }
        }
      } catch {
        print("Failed to remove book: \(error)")
      }
    }
  }

  override func onCreateCollection() {
    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    Task {
      do {
        let newCollection: any CollectionLike

        switch mode {
        case .playlists:
          newCollection = try await audiobookshelf.playlists.create(
            name: name,
            items: [bookID],
            episodeID: episodeID
          )
        case .collections:
          newCollection = try await audiobookshelf.collections.create(
            name: name,
            items: [bookID]
          )
        }

        let newCollectionItem = CollectionRowModel(collection: newCollection)

        playlists.insert(newCollectionItem, at: 0)
        playlistsContainingBook.insert(newCollection.id)
        newPlaylistName = ""
      } catch {
        print("Failed to create: \(error)")
      }
    }
  }

  private func loadCollections() async {
    isLoading = true

    do {
      switch mode {
      case .playlists:
        let response = try await audiobookshelf.playlists.fetch(limit: 100, page: 0)

        playlists = response.results.map { playlist in
          CollectionRowModel(collection: playlist)
        }

        if let episodeID {
          playlistsContainingBook = Set(
            response.results
              .filter { $0.items.contains { $0.libraryItemID == bookID && $0.episodeID == episodeID } }
              .map { $0.id }
          )
        } else {
          playlistsContainingBook = Set(
            response.results
              .filter { $0.books.contains { $0.id == bookID } }
              .map { $0.id }
          )
        }

      case .collections:
        let response = try await audiobookshelf.collections.fetch(limit: 100, page: 0)

        playlists = response.results.map { collection in
          CollectionRowModel(collection: collection)
        }

        playlistsContainingBook = Set(
          response.results
            .filter { $0.books.contains { $0.id == bookID } }
            .map { $0.id }
        )
      }
    } catch {
      playlists = []
      playlistsContainingBook = []
      print("Failed to load collections: \(error)")
    }

    isLoading = false
  }
}
