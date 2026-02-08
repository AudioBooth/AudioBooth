import Foundation

public final class PodcastsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil,
    sortBy: SortBy? = nil,
    ascending: Bool = true,
    filter: String? = nil
  ) async throws -> Page<Podcast> {
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

    var query: [String: String] = [
      "minified": "1",
      "include": "rssfeed,numEpisodesIncomplete,share",
    ]

    if let limit {
      query["limit"] = String(limit)
    }
    if let page {
      query["page"] = String(page)
    }
    if let sortBy {
      query["sort"] = sortBy.rawValue
    }
    if !ascending {
      query["desc"] = "1"
    }
    if let filter {
      query["filter"] = filter
    }

    let request = NetworkRequest<Page<Podcast>>(
      path: "/api/libraries/\(library.id)/items",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetch(id: String) async throws -> Podcast {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let query: [String: String] = ["expanded": "1"]

    let request = NetworkRequest<Podcast>(
      path: "/api/items/\(id)",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }
}
