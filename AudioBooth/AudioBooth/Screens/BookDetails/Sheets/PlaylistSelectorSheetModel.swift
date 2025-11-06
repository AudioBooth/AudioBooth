import API
import Foundation

final class PlaylistSelectorSheetModel: PlaylistSelectorSheet.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let bookID: String

  init(bookID: String) {
    self.bookID = bookID
    super.init()
  }

  override func onAppear() {
    Task {
      await loadPlaylists()
    }
  }

  override func onAddToPlaylist(_ playlist: PlaylistRow.Model) {
    Task {
      do {
        let updatedPlaylist = try await audiobookshelf.playlists.addItems(
          playlistID: playlist.id,
          items: [bookID]
        )

        playlistsContainingBook.insert(playlist.id)
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          playlists[index] = PlaylistRowModel(playlist: updatedPlaylist)
        }
      } catch {
        print("Failed to add book to playlist: \(error)")
      }
    }
  }

  override func onRemoveFromPlaylist(_ playlist: PlaylistRow.Model) {
    Task {
      do {
        let updatedPlaylist = try await audiobookshelf.playlists.removeItem(
          playlistID: playlist.id,
          libraryItemID: bookID
        )

        playlistsContainingBook.remove(playlist.id)

        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          if updatedPlaylist.items.isEmpty {
            playlists.remove(at: index)
          } else {
            playlists[index] = PlaylistRowModel(playlist: updatedPlaylist)
          }
        }
      } catch {
        print("Failed to remove book from playlist: \(error)")
      }
    }
  }

  override func onCreatePlaylist() {
    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    Task {
      do {
        let playlist = try await audiobookshelf.playlists.create(
          name: name,
          items: [bookID]
        )

        let newPlaylistItem = PlaylistRowModel(playlist: playlist)

        playlists.insert(newPlaylistItem, at: 0)
        playlistsContainingBook.insert(playlist.id)
        newPlaylistName = ""
      } catch {
        print("Failed to create playlist: \(error)")
      }
    }
  }

  private func loadPlaylists() async {
    isLoading = true

    do {
      let response = try await audiobookshelf.playlists.fetch(limit: 100, page: 0)

      playlists = response.results.map { playlist in
        PlaylistRowModel(playlist: playlist)
      }

      playlistsContainingBook = Set(
        response.results
          .filter { $0.items.contains { $0.libraryItemID == bookID } }
          .map { $0.id }
      )
    } catch {
      playlists = []
      playlistsContainingBook = []
      print("Failed to load playlists: \(error)")
    }

    isLoading = false
  }
}
