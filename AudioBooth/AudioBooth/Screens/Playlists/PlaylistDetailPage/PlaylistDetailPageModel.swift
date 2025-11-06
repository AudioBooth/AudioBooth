import API
import Foundation
import SwiftUI

final class PlaylistDetailPageModel: PlaylistDetailPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playlistID: String
  private var loadTask: Task<Void, Never>?

  var onDeleted: (() -> Void)?

  init(playlistID: String) {
    self.playlistID = playlistID
    super.init()
  }

  override func onAppear() {
    guard books.isEmpty else { return }

    loadTask = Task {
      await loadPlaylist()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    await loadPlaylist()
  }

  override func onDeletePlaylist() {
    Task {
      do {
        try await audiobookshelf.playlists.delete(playlistID: playlistID)
        NotificationCenter.default.post(
          name: .playlistDeleted,
          object: nil,
          userInfo: ["playlistID": playlistID]
        )
        onDeleted?()
      } catch {
        print("Failed to delete playlist: \(error)")
      }
    }
  }

  override func onUpdatePlaylist(name: String, description: String?) {
    Task {
      do {
        let updatedPlaylist = try await audiobookshelf.playlists.update(
          playlistID: playlistID,
          name: name,
          description: description
        )

        playlistName = updatedPlaylist.name
        playlistDescription = updatedPlaylist.description
      } catch {
        print("Failed to update playlist: \(error)")
        await loadPlaylist()
      }
    }
  }

  override func onMove(from source: IndexSet, to destination: Int) {
    books.move(fromOffsets: source, toOffset: destination)

    Task {
      do {
        let bookIDs = books.map { $0.id }
        let updatedPlaylist = try await audiobookshelf.playlists.update(
          playlistID: playlistID,
          items: bookIDs
        )

        books = updatedPlaylist.items.map { item in
          ItemRowModel(item.libraryItem)
        }
      } catch {
        print("Failed to reorder playlist items: \(error)")
        await loadPlaylist()
      }
    }
  }

  override func onDelete(at indexSet: IndexSet) {
    let idsToRemove = indexSet.map { books[$0].id }

    Task {
      do {
        let updatedPlaylist = try await audiobookshelf.playlists.removeItems(
          playlistID: playlistID,
          items: idsToRemove
        )

        if updatedPlaylist.items.isEmpty {
          NotificationCenter.default.post(
            name: .playlistDeleted,
            object: nil,
            userInfo: ["playlistID": playlistID]
          )
          onDeleted?()
        } else {
          books = updatedPlaylist.items.map { item in
            ItemRowModel(item.libraryItem)
          }
        }
      } catch {
        print("Failed to remove items from playlist: \(error)")
        await loadPlaylist()
      }
    }
  }

  private func loadPlaylist() async {
    isLoading = true

    do {
      let playlist = try await audiobookshelf.playlists.fetch(id: playlistID)

      guard !Task.isCancelled else {
        isLoading = false
        return
      }

      playlistName = playlist.name
      playlistDescription = playlist.description

      books = playlist.items.map { item in
        ItemRowModel(item.libraryItem)
      }
    } catch {
      guard !Task.isCancelled else {
        isLoading = false
        return
      }

      books = []
      print("Failed to load playlist: \(error)")
    }

    isLoading = false
    loadTask = nil
  }
}
