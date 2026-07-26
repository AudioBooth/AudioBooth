import Foundation

public final class CollectionsService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetch(
    limit: Int? = nil,
    page: Int? = nil
  ) async throws -> Page<Collection> {
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

    var query: [String: String] = [:]

    if let limit {
      query["limit"] = String(limit)
    }
    if let page {
      query["page"] = String(page)
    }

    let request = NetworkRequest<Page<Collection>>(
      path: "/api/libraries/\(library.id)/collections",
      method: .get,
      query: query
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func fetch(id: String) async throws -> Collection {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Collection>(
      path: "/api/collections/\(id)",
      method: .get
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func removeItem(collectionID: String, libraryItemID: String) async throws -> Collection {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Collection>(
      path: "/api/collections/\(collectionID)/book/\(libraryItemID)",
      method: .delete
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func removeItems(collectionID: String, items: [String]) async throws -> Collection {
    struct CollectionItem: Codable {
      let libraryItemID: String

      private enum CodingKeys: String, CodingKey {
        case libraryItemID = "libraryItemId"
      }
    }

    struct RemoveItemsRequest: Codable {
      let books: [String]
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let requestBody = RemoveItemsRequest(books: items)

    let request = NetworkRequest<Collection>(
      path: "/api/collections/\(collectionID)/batch/remove",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func create(name: String, items: [String]) async throws -> Collection {
    struct CreateCollectionRequest: Codable {
      let books: [String]
      let libraryID: String
      let name: String
      let description: String?

      private enum CodingKeys: String, CodingKey {
        case books
        case libraryID = "libraryId"
        case name
        case description
      }
    }

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

    let requestBody = CreateCollectionRequest(
      books: items,
      libraryID: library.id,
      name: name,
      description: nil
    )

    let request = NetworkRequest<Collection>(
      path: "/api/collections",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func addItems(collectionID: String, items: [String]) async throws -> Collection {
    struct AddItemsRequest: Codable {
      let books: [String]
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let requestBody = AddItemsRequest(books: items)

    let request = NetworkRequest<Collection>(
      path: "/api/collections/\(collectionID)/batch/add",
      method: .post,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func update(
    collectionID: String,
    name: String? = nil,
    description: String? = nil,
    items: [String]? = nil
  ) async throws -> Collection {
    struct UpdateCollectionRequest: Codable {
      let name: String?
      let description: String?
      let books: [String]?
    }

    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let requestBody = UpdateCollectionRequest(
      name: name,
      description: description,
      books: items
    )

    let request = NetworkRequest<Collection>(
      path: "/api/collections/\(collectionID)",
      method: .patch,
      body: requestBody
    )

    let response = try await networkService.send(request)
    return response.value
  }

  public func delete(collectionID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/collections/\(collectionID)",
      method: .delete
    )

    _ = try await networkService.send(request)
  }
}
