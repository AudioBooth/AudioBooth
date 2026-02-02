import API
import Foundation
import SwiftUI

final class CollectionDetailPageModel: CollectionDetailPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let pinnedPlaylistManager = PinnedPlaylistManager.shared
  private let collectionID: String
  private var loadTask: Task<Void, Never>?

  var onDeleted: (() -> Void)?

  init(collectionID: String, mode: CollectionMode) {
    self.collectionID = collectionID

    let permissions = Audiobookshelf.shared.authentication.permissions
    let canEdit: Bool
    let canDelete: Bool

    switch mode {
    case .playlists:
      canEdit = true
      canDelete = true
    case .collections:
      canEdit = permissions?.update == true
      canDelete = permissions?.delete == true
    }

    let isPinned = pinnedPlaylistManager.isPinned(collectionID)

    super.init(mode: mode, canEdit: canEdit, canDelete: canDelete, isPinned: isPinned)
  }

  override func onAppear() {
    guard books.isEmpty else { return }

    loadTask = Task {
      await loadCollection()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    await loadCollection()
  }

  override func onDeleteCollection() {
    Task {
      do {
        switch mode {
        case .playlists:
          try await audiobookshelf.playlists.delete(playlistID: collectionID)
        case .collections:
          try await audiobookshelf.collections.delete(collectionID: collectionID)
        }
        onDeleted?()
      } catch {
        print("Failed to delete: \(error)")
      }
    }
  }

  override func onUpdateCollection(name: String, description: String?) {
    Task {
      do {
        switch mode {
        case .playlists:
          let updatedPlaylist = try await audiobookshelf.playlists.update(
            playlistID: collectionID,
            name: name,
            description: description
          )
          collectionName = updatedPlaylist.name
          collectionDescription = updatedPlaylist.description
        case .collections:
          let updatedCollection = try await audiobookshelf.collections.update(
            collectionID: collectionID,
            name: name,
            description: description
          )
          collectionName = updatedCollection.name
          collectionDescription = updatedCollection.description
        }
      } catch {
        print("Failed to update: \(error)")
        await loadCollection()
      }
    }
  }

  override func onMove(from source: IndexSet, to destination: Int) {
    books.move(fromOffsets: source, toOffset: destination)

    Task {
      do {
        let bookIDs = books.map { $0.id }

        switch mode {
        case .playlists:
          let updatedPlaylist = try await audiobookshelf.playlists.update(
            playlistID: collectionID,
            items: bookIDs
          )
          books = updatedPlaylist.books.map { book in
            BookCardModel(book, sortBy: nil)
          }
        case .collections:
          let updatedCollection = try await audiobookshelf.collections.update(
            collectionID: collectionID,
            items: bookIDs
          )
          books = updatedCollection.books.map { book in
            BookCardModel(book, sortBy: nil)
          }
        }
      } catch {
        print("Failed to reorder items: \(error)")
        await loadCollection()
      }
    }
  }

  override func onDelete(at indexSet: IndexSet) {
    let idsToRemove = indexSet.map { books[$0].id }

    Task {
      do {
        let updatedCollection: any CollectionLike

        switch mode {
        case .playlists:
          updatedCollection = try await audiobookshelf.playlists.removeItems(
            playlistID: collectionID,
            items: idsToRemove
          )

          if updatedCollection.books.isEmpty, mode == .playlists {
            onDeleted?()
            return
          }

        case .collections:
          updatedCollection = try await audiobookshelf.collections.removeItems(
            collectionID: collectionID,
            items: idsToRemove
          )
        }

        books = updatedCollection.books.map { book in
          BookCardModel(book, sortBy: nil)
        }
      } catch {
        print("Failed to remove items: \(error)")
        await loadCollection()
      }
    }
  }

  override func onTogglePin() {
    if isPinned {
      pinnedPlaylistManager.unpin()
      isPinned = false
    } else {
      pinnedPlaylistManager.pin(collectionID)
      isPinned = true
    }
  }

  private func loadCollection() async {
    isLoading = true

    do {
      let collection: any CollectionLike

      switch mode {
      case .playlists:
        collection = try await audiobookshelf.playlists.fetch(id: collectionID)
      case .collections:
        collection = try await audiobookshelf.collections.fetch(id: collectionID)
      }

      guard !Task.isCancelled else {
        isLoading = false
        return
      }

      collectionName = collection.name
      collectionDescription = collection.description

      books = collection.books.map { book in
        BookCardModel(book, sortBy: nil)
      }
    } catch {
      guard !Task.isCancelled else {
        isLoading = false
        return
      }

      books = []
      print("Failed to load collection: \(error)")
    }

    isLoading = false
    loadTask = nil
  }
}
