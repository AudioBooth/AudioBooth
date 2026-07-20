import API
import Foundation
import Logging

final class CollectionSelectorSheetModel: CollectionSelectorSheet.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let bookIDs: [String]
  private let episodeID: String?

  convenience init(bookID: String, episodeID: String? = nil, mode: CollectionMode = .playlists) {
    self.init(bookIDs: [bookID], episodeID: episodeID, mode: mode)
  }

  init(bookIDs: [String], episodeID: String? = nil, mode: CollectionMode = .playlists) {
    self.bookIDs = bookIDs
    self.episodeID = episodeID

    let canEdit: Bool
    switch mode {
    case .playlists:
      canEdit = true
    case .collections:
      canEdit = audiobookshelf.authentication.server?.permissions?.update == true
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
            items: bookIDs,
            episodeID: episodeID
          )
        case .collections:
          updatedCollection = try await audiobookshelf.collections.addItems(
            collectionID: playlist.id,
            items: bookIDs
          )
        }

        playlistsContainingBook.insert(playlist.id)
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          playlists[index] = CollectionRowModel(collection: updatedCollection)
        }
      } catch {
        AppLogger.viewModel.error("Failed to add book: \(error)")
      }
    }
  }

  override func onRemoveFromPlaylist(_ playlist: CollectionRow.Model) {
    Task {
      do {
        let updatedCollection: any CollectionLike

        switch mode {
        case .playlists:
          if let episodeID {
            updatedCollection = try await audiobookshelf.playlists.removeItem(
              playlistID: playlist.id,
              libraryItemID: bookIDs[0],
              episodeID: episodeID
            )
          } else {
            updatedCollection = try await audiobookshelf.playlists.removeItems(
              playlistID: playlist.id,
              items: bookIDs.map { (libraryItemID: $0, episodeID: nil) }
            )
          }
        case .collections:
          updatedCollection = try await audiobookshelf.collections.removeItems(
            collectionID: playlist.id,
            items: bookIDs
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
        AppLogger.viewModel.error("Failed to remove book: \(error)")
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
            items: bookIDs,
            episodeID: episodeID
          )
        case .collections:
          newCollection = try await audiobookshelf.collections.create(
            name: name,
            items: bookIDs
          )
        }

        let newCollectionItem = CollectionRowModel(collection: newCollection)

        playlists.insert(newCollectionItem, at: 0)
        playlistsContainingBook.insert(newCollection.id)
        newPlaylistName = ""
      } catch {
        AppLogger.viewModel.error("Failed to create: \(error)")
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
              .filter { $0.items.contains { $0.libraryItemID == bookIDs[0] && $0.episodeID == episodeID } }
              .map { $0.id }
          )
        } else {
          playlistsContainingBook = Set(
            response.results
              .filter { playlist in bookIDs.allSatisfy { id in playlist.books.contains { $0.id == id } } }
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
            .filter { collection in bookIDs.allSatisfy { id in collection.books.contains { $0.id == id } } }
            .map { $0.id }
        )
      }
    } catch {
      playlists = []
      playlistsContainingBook = []
      AppLogger.viewModel.error("Failed to load collections: \(error)")
    }

    isLoading = false
  }
}
