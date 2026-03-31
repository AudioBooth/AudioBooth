import Foundation

public final class SeriesService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public enum SortBy: String, CaseIterable {
    case name
    case numBooks
    case addedAt
    case lastBookAdded
    case lastBookUpdated
    case totalDuration
    case random

    public var displayTitle: LocalizedStringResource {
      switch self {
      case .name: "Name"
      case .numBooks: "Number of Books"
      case .addedAt: "Date Added"
      case .lastBookAdded: "Last Book Added"
      case .lastBookUpdated: "Last Book Updated"
      case .totalDuration: "Total Duration"
      case .random: "Randomly"
      }
    }
  }

  public func fetch(
    limit: Int,
    page: Int? = nil,
    sortBy: SortBy? = nil,
    ascending: Bool = true
  ) async throws -> Page<Series> {
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

    var queryParams: [String: String] = [:]
    queryParams["limit"] = String(limit)

    if let page {
      queryParams["page"] = String(page)
    }
    if let sortBy {
      queryParams["sort"] = sortBy.rawValue
    }
    if !ascending {
      queryParams["desc"] = "1"
    }

    let request = NetworkRequest<Page<Series>>(
      path: "/api/libraries/\(library.id)/series",
      method: .get,
      query: queryParams
    )

    let response = try await networkService.send(request)
    return response.value
  }
}
