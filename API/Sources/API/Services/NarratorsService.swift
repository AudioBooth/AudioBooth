import Foundation

public final class NarratorsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetch() async throws -> [Narrator] {
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

    struct Response: Codable {
      let narrators: [Narrator]
    }

    let request = NetworkRequest<Response>(
      path: "/api/libraries/\(library.id)/narrators",
      method: .get
    )

    let response = try await networkService.send(request)
    return response.value.narrators
  }
}
