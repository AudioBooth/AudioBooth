import Foundation

public final class PlaylistsService {
  private let audiobookshelf: Audiobookshelf
  private let pinnedPlaylistKey = "cached_pinned_playlist"

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public var pinnedPlaylist: Playlist? {
    get {
      guard let data = UserDefaults.standard.data(forKey: pinnedPlaylistKey) else { return nil }
      return try? JSONDecoder().decode(Playlist.self, from: data)
    }
    set {
      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.standard.set(data, forKey: pinnedPlaylistKey)
      } else {
        UserDefaults.standard.removeObject(forKey: pinnedPlaylistKey)
      }
    }
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil
  ) async throws -> Page<Playlist> {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    guard let library = audiobookshelf.libraries.current else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "No library selected. Please select a library first."
      )
    }

    var query: [String: String] = [:]

    if let limit {
      query["limit"] = String(limit)
    }
    if let page {
      query["page"] = String(page)
    }

    let request = NetworkRequest<Page<Playlist>>(
      path: "/api/libraries/\(library.id)/playlists",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetch(id: String) async throws -> Playlist {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Playlist>(
      path: "/api/playlists/\(id)",
      method: .get
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func removeItem(
    playlistID: String,
    libraryItemID: String,
    episodeID: String? = nil
  ) async throws -> Playlist {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    var path = "/api/playlists/\(playlistID)/item/\(libraryItemID)"
    if let episodeID {
      path += "/\(episodeID)"
    }

    let request = NetworkRequest<Playlist>(
      path: path,
      method: .delete
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func removeItems(playlistID: String, items: [String]) async throws -> Playlist {
    struct PlaylistItem: Codable {
      let libraryItemID: String
      let episodeID: String?

      private enum CodingKeys: String, CodingKey {
        case libraryItemID = "libraryItemId"
        case episodeID = "episodeId"
      }
    }

    struct RemoveItemsRequest: Codable {
      let items: [PlaylistItem]
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let playlistItems = items.map { PlaylistItem(libraryItemID: $0, episodeID: nil) }
    let requestBody = RemoveItemsRequest(items: playlistItems)

    let request = NetworkRequest<Playlist>(
      path: "/api/playlists/\(playlistID)/batch/remove",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func create(name: String, items: [String], episodeID: String? = nil) async throws -> Playlist {
    struct PlaylistItem: Codable {
      let libraryItemID: String
      let episodeID: String?

      private enum CodingKeys: String, CodingKey {
        case libraryItemID = "libraryItemId"
        case episodeID = "episodeId"
      }
    }

    struct CreatePlaylistRequest: Codable {
      let items: [PlaylistItem]
      let libraryID: String
      let name: String

      private enum CodingKeys: String, CodingKey {
        case items
        case libraryID = "libraryId"
        case name
      }
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    guard let library = audiobookshelf.libraries.current else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "No library selected. Please select a library first."
      )
    }

    let playlistItems = items.map { PlaylistItem(libraryItemID: $0, episodeID: episodeID) }
    let requestBody = CreatePlaylistRequest(
      items: playlistItems,
      libraryID: library.id,
      name: name
    )

    let request = NetworkRequest<Playlist>(
      path: "/api/playlists",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func addItems(playlistID: String, items: [String], episodeID: String? = nil) async throws -> Playlist {
    struct PlaylistItem: Codable {
      let libraryItemID: String
      let episodeID: String?

      private enum CodingKeys: String, CodingKey {
        case libraryItemID = "libraryItemId"
        case episodeID = "episodeId"
      }
    }

    struct AddItemsRequest: Codable {
      let items: [PlaylistItem]
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let playlistItems = items.map { PlaylistItem(libraryItemID: $0, episodeID: episodeID) }
    let requestBody = AddItemsRequest(items: playlistItems)

    let request = NetworkRequest<Playlist>(
      path: "/api/playlists/\(playlistID)/batch/add",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func update(
    playlistID: String,
    name: String? = nil,
    description: String? = nil,
    items: [String]? = nil
  ) async throws -> Playlist {
    struct PlaylistItem: Codable {
      let libraryItemID: String

      private enum CodingKeys: String, CodingKey {
        case libraryItemID = "libraryItemId"
      }
    }

    struct UpdatePlaylistRequest: Codable {
      let name: String?
      let description: String?
      let items: [PlaylistItem]?
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let playlistItems = items?.map { PlaylistItem(libraryItemID: $0) }
    let requestBody = UpdatePlaylistRequest(
      name: name,
      description: description,
      items: playlistItems
    )

    let request = NetworkRequest<Playlist>(
      path: "/api/playlists/\(playlistID)",
      method: .patch,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func delete(playlistID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/playlists/\(playlistID)",
      method: .delete
    )

    _ = try await networkService.send(request)
  }
}
