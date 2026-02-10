import API
import Foundation
import Models
import SwiftUI

final class CollectionDetailPageModel: CollectionDetailPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared
  private let pinnedPlaylistManager = PinnedPlaylistManager.shared
  private let collectionID: String
  private var loadTask: Task<Void, Never>?
  private var playlistItems: [PlaylistItem] = []

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
          books = mapPlaylistItems(updatedPlaylist)
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
        switch mode {
        case .playlists:
          let updatedPlaylist = try await audiobookshelf.playlists.removeItems(
            playlistID: collectionID,
            items: idsToRemove
          )

          if updatedPlaylist.items.isEmpty {
            onDeleted?()
            return
          }

          books = mapPlaylistItems(updatedPlaylist)

        case .collections:
          let updatedCollection = try await audiobookshelf.collections.removeItems(
            collectionID: collectionID,
            items: idsToRemove
          )
          books = updatedCollection.books.map { book in
            BookCardModel(book, sortBy: nil)
          }
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

  override func onPlayItem(_ item: BookCard.Model) {
    guard let podcastID = item.podcastID,
      let playlistItem = playlistItems.first(where: { $0.episodeID == item.id }),
      let episode = playlistItem.episode
    else { return }

    if playerManager.current?.id == item.id {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.onTogglePlaybackTapped()
      }
    } else {
      let podcast: Podcast? = if case .podcast(let p) = playlistItem.libraryItem { p } else { nil }
      playerManager.setCurrent(
        episode: episode,
        podcastID: podcastID,
        podcastTitle: podcast?.title ?? "",
        podcastAuthor: podcast?.author,
        coverURL: item.cover.url
      )
      playerManager.play()
    }
  }

  private func loadCollection() async {
    isLoading = true

    do {
      switch mode {
      case .playlists:
        let playlist = try await audiobookshelf.playlists.fetch(id: collectionID)

        guard !Task.isCancelled else {
          isLoading = false
          return
        }

        collectionName = playlist.name
        collectionDescription = playlist.description
        books = mapPlaylistItems(playlist)

      case .collections:
        let collection = try await audiobookshelf.collections.fetch(id: collectionID)

        guard !Task.isCancelled else {
          isLoading = false
          return
        }

        collectionName = collection.name
        collectionDescription = collection.description
        books = collection.books.map { book in
          BookCardModel(book, sortBy: nil)
        }
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

  private func mapPlaylistItems(_ playlist: Playlist) -> [BookCard.Model] {
    playlistItems = playlist.items
    return playlist.items.map { item in
      if let episode = item.episode {
        let durationText = episode.duration.map {
          Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        return BookCard.Model(
          id: episode.id,
          podcastID: item.libraryItemID,
          title: episode.title,
          details: durationText,
          cover: Cover.Model(
            url: item.coverURL,
            progress: MediaProgress.progress(for: episode.id)
          ),
          author: item.title
        )
      } else if case .book(let book) = item.libraryItem {
        return BookCardModel(book, sortBy: nil)
      } else {
        return BookCard.Model(
          id: item.libraryItemID,
          title: item.title,
          cover: Cover.Model(url: item.coverURL)
        )
      }
    }
  }
}
