import API
import Foundation

final class PlaylistRowModel: PlaylistRow.Model {
  init(playlist: Playlist) {
    super.init(
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      count: playlist.items.count,
      covers: playlist.covers
    )
  }
}
