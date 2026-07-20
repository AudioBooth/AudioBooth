import Foundation

public final class SearchService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func search(query: String) async throws -> SearchResponse {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    guard let library = await audiobookshelf.libraries.current else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "No library selected. Please select a library first."
      )
    }

    let request = NetworkRequest<SearchResponse>(
      path: "/api/libraries/\(library.id)/search",
      method: .get,
      query: ["q": query]
    )

    let response = try await networkService.send(request)
    return response.value
  }
}
