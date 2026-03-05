import Foundation

public final class AuthorsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public enum SortBy: String, CaseIterable, Hashable {
    case name
    case lastFirst
    case numBooks
    case addedAt
    case updatedAt
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil,
    sortBy: SortBy? = nil,
    ascending: Bool = true
  ) async throws -> Page<Author> {
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

    var query: [String: String] = ["minified": "1"]

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

    let request = NetworkRequest<Page<Author>>(
      path: "/api/libraries/\(library.id)/authors",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetchDetails(authorID: String) async throws -> AuthorDetails {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let query: [String: String] = ["include": "items,series"]

    let request = NetworkRequest<AuthorDetails>(
      path: "/api/authors/\(authorID)",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }
}
