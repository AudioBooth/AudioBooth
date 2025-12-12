import Foundation

public final class BooksService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public enum SortBy: String {
    case title = "media.metadata.title"
    case authorName = "media.metadata.authorName"
    case authorNameLF = "media.metadata.authorNameLF"
    case publishedYear = "media.metadata.publishedYear"
    case addedAt
    case size
    case duration = "media.duration"
    case updatedAt
    case progress
    case progressFinishedAt = "progress.finishedAt"
    case progressCreatedAt = "progress.createdAt"
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil,
    sortBy: SortBy? = nil,
    ascending: Bool = true,
    collapseSeries: Bool = false,
    filter: String? = nil
  ) async throws -> Page<Book> {
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
    if collapseSeries {
      query["collapseseries"] = "1"
    }
    if let filter {
      query["filter"] = filter
    }

    let request = NetworkRequest<Page<Book>>(
      path: "/api/libraries/\(library.id)/items",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetch(id: String) async throws -> Book {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let query: [String: String] = ["expanded": "1"]

    let request = NetworkRequest<Book>(
      path: "/api/items/\(id)",
      method: .get,
      query: query
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw error
    }
  }

  public func updateEbookProgress(bookID: String, progress: Double) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct ProgressUpdate: Encodable {
      let ebookProgress: Double
      let ebookLocation: String
    }

    let body = ProgressUpdate(ebookProgress: progress, ebookLocation: "")

    let request = NetworkRequest<Data>(
      path: "/api/me/progress/\(bookID)",
      method: .patch,
      body: body
    )

    _ = try await networkService.send(request)
  }
}
