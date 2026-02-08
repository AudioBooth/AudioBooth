import Foundation

public final class PodcastsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public enum SortBy: String {
    case title = "media.metadata.title"
    case author = "media.metadata.author"
    case addedAt
    case size
    case updatedAt
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
}
