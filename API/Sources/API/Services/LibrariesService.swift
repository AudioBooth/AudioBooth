import Combine
import Foundation
import Logging
import Nuke

public final class LibrariesService: ObservableObject, @unchecked Sendable {
  private let audiobookshelf: Audiobookshelf
  private let userDefaults = UserDefaults.standard

  enum Keys {
    static let library = "selected_library"
    static func personalized(libraryID: String) -> String {
      "personalized_\(libraryID)"
    }
    static func filterData(libraryID: String) -> String {
      "filterdata_\(libraryID)"
    }

    static let sortingIgnorePrefix = "sortingIgnorePrefix"
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
    migrateUserDefaultsIfNeeded()
  }

  private func migrateUserDefaultsIfNeeded() {
    guard userDefaults.data(forKey: Keys.library) == nil else { return }

    if let libraryData = userDefaults.data(forKey: "audiobookshelf_selected_library") {
      userDefaults.set(libraryData, forKey: Keys.library)
      userDefaults.removeObject(forKey: "audiobookshelf_selected_library")
      AppLogger.libraries.info("Migrated library selection to App Group UserDefaults")
    }
  }

  public var current: Library? {
    get {
      guard let data = userDefaults.data(forKey: Keys.library) else { return nil }
      return try? JSONDecoder().decode(Library.self, from: data)
    }
    set {
      objectWillChange.send()
      if let newValue {
        guard let data = try? JSONEncoder().encode(newValue) else { return }
        userDefaults.set(data, forKey: Keys.library)
      } else {
        userDefaults.removeObject(forKey: Keys.library)
      }
      ImagePipeline.shared.cache.removeAll()
    }
  }

  public var sortingIgnorePrefix: Bool {
    get {
      UserDefaults.standard.bool(forKey: Keys.sortingIgnorePrefix)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.sortingIgnorePrefix)
    }
  }

  public func fetch(serverID: String? = nil) async throws -> [Library] {
    let networkService: NetworkService

    if let serverID {
      guard let server = audiobookshelf.authentication.servers[serverID] else {
        throw Audiobookshelf.AudiobookshelfError.networkError("Server not found")
      }
      networkService = NetworkService(baseURL: server.baseURL, server: server) {
        let freshToken = try? await server.freshToken
        guard let credentials = freshToken else {
          return [:]
        }

        var headers = server.customHeaders
        headers["Authorization"] = credentials.bearer
        return headers
      }
    } else {
      guard let service = audiobookshelf.networkService else {
        throw Audiobookshelf.AudiobookshelfError.networkError(
          "Network service not configured. Please login first."
        )
      }
      networkService = service
    }

    struct Response: Codable {
      let libraries: [Library]
    }

    let request = NetworkRequest<Response>(
      path: "/api/libraries",
      method: .get
    )

    do {
      let response = try await networkService.send(request)
      return response.value.libraries
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch libraries: \(error.localizedDescription)"
      )
    }
  }

  public func getCachedPersonalized() -> Personalized? {
    guard let library = audiobookshelf.libraries.current else { return nil }
    let key = Keys.personalized(libraryID: library.id)
    guard let data = userDefaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Personalized.self, from: data)
  }

  public func fetchPersonalized() async throws -> Personalized {
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

    let request = NetworkRequest<[Personalized.Section]>(
      path: "/api/libraries/\(library.id)/personalized",
      method: .get
    )

    do {
      let response = try await networkService.send(request)

      let personalized = Personalized(libraryID: library.id, sections: response.value)

      let encoder = JSONEncoder()
      if let data = try? encoder.encode(personalized) {
        let key = Keys.personalized(libraryID: personalized.libraryID)
        userDefaults.set(data, forKey: key)
      }

      return personalized
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch personalized sections: \(error.localizedDescription)"
      )
    }
  }

  public func markAsFinished(bookID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct UpdateFinishedStatusRequest: Codable {
      let isFinished: Bool
    }

    let request = NetworkRequest<Data>(
      path: "/api/me/progress/\(bookID)",
      method: .patch,
      body: UpdateFinishedStatusRequest(isFinished: true)
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to update book finished status: \(error.localizedDescription)"
      )
    }
  }

  public func fetchMediaProgress(bookID: String) async throws -> User.MediaProgress {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<User.MediaProgress>(
      path: "/api/me/progress/\(bookID)",
      method: .get
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch media progress: \(error.localizedDescription)"
      )
    }
  }

  public func resetBookProgress(progressID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/me/progress/\(progressID)",
      method: .delete
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to reset book progress: \(error.localizedDescription)"
      )
    }
  }

  public func getCachedFilterData() -> FilterData? {
    guard let library = audiobookshelf.libraries.current else { return nil }
    let key = Keys.filterData(libraryID: library.id)
    guard let data = userDefaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(FilterData.self, from: data)
  }

  public func fetchFilterData() async throws -> FilterData {
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

    struct Response: Codable {
      let filterdata: FilterData
    }

    let request = NetworkRequest<Response>(
      path: "/api/libraries/\(library.id)",
      method: .get,
      query: ["include": "filterdata"]
    )

    do {
      let response = try await networkService.send(request)

      let encoder = JSONEncoder()
      if let data = try? encoder.encode(response.value.filterdata) {
        let key = Keys.filterData(libraryID: library.id)
        userDefaults.set(data, forKey: key)
      }

      return response.value.filterdata
    } catch {
      print("❌ FilterData decoding error: \(error)")
      if let decodingError = error as? DecodingError {
        switch decodingError {
        case .keyNotFound(let key, let context):
          print("  Missing key: \(key.stringValue) at path: \(context.codingPath)")
        case .typeMismatch(let type, let context):
          print("  Type mismatch for type: \(type) at path: \(context.codingPath)")
        case .valueNotFound(let type, let context):
          print("  Value not found for type: \(type) at path: \(context.codingPath)")
        case .dataCorrupted(let context):
          print("  Data corrupted at path: \(context.codingPath)")
        @unknown default:
          print("  Unknown decoding error")
        }
      }
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch filter data: \(error.localizedDescription)"
      )
    }
  }
}
