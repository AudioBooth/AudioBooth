import Foundation
import Logging

@MainActor
public final class FilterDataService {
  private let audiobookshelf: Audiobookshelf

  private var cachedData: (libraryID: String, data: FilterData)?
  private var cachedLookups: Lookups?
  private var activeFetch: (id: UUID, libraryID: String, task: Task<FilterData, Error>)?

  private struct Lookups {
    let libraryID: String
    let authors: [String: FilterData.Author]
    let series: [String: FilterData.Series]
  }

  private static func storageKey(libraryID: String) -> String {
    "filterdata_\(libraryID)"
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func cached() -> FilterData? {
    guard let library = audiobookshelf.libraries.current else { return nil }

    if let cachedData, cachedData.libraryID == library.id {
      return cachedData.data
    }

    let key = Self.storageKey(libraryID: library.id)
    guard let data = audiobookshelf.authentication.server?.storage.data(forKey: key),
      let decoded = try? JSONDecoder().decode(FilterData.self, from: data)
    else { return nil }

    cachedData = (library.id, decoded)
    return decoded
  }

  public func author(named name: String) -> FilterData.Author? {
    lookups()?.authors[name]
  }

  public func series(named name: String) -> FilterData.Series? {
    lookups()?.series[name]
  }

  public func clearCache() {
    cachedData = nil
    cachedLookups = nil

    guard let storage = audiobookshelf.authentication.server?.storage else { return }
    for key in storage.dictionaryRepresentation().keys where key.hasPrefix("filterdata_") {
      storage.removeObject(forKey: key)
    }
  }

  public func fetch() async throws -> FilterData {
    guard let library = audiobookshelf.libraries.current else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "No library selected. Please select a library first."
      )
    }

    if let activeFetch, activeFetch.libraryID == library.id {
      return try await activeFetch.task.value
    }

    activeFetch?.task.cancel()

    let id = UUID()
    let task = Task { try await performFetch(library: library) }
    activeFetch = (id, library.id, task)
    defer { if activeFetch?.id == id { activeFetch = nil } }

    return try await task.value
  }

  private func lookups() -> Lookups? {
    guard let library = audiobookshelf.libraries.current else { return nil }

    if let cachedLookups, cachedLookups.libraryID == library.id {
      return cachedLookups
    }

    guard let data = cached() else { return nil }

    let lookups = Lookups(
      libraryID: library.id,
      authors: Dictionary(data.authors.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }),
      series: Dictionary(data.series.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    )

    cachedLookups = lookups
    return lookups
  }

  private func performFetch(library: Library) async throws -> FilterData {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
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
      try Task.checkCancellation()

      cachedData = (library.id, response.value.filterdata)
      cachedLookups = nil

      let encoder = JSONEncoder()
      if let data = try? encoder.encode(response.value.filterdata) {
        let key = Self.storageKey(libraryID: library.id)
        audiobookshelf.authentication.server?.storage.set(data, forKey: key)
      }

      return response.value.filterdata
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      AppLogger.libraries.error("FilterData decoding error: \(error)")
      if let decodingError = error as? DecodingError {
        switch decodingError {
        case .keyNotFound(let key, let context):
          AppLogger.libraries.error("Missing key: \(key.stringValue) at path: \(context.codingPath)")
        case .typeMismatch(let type, let context):
          AppLogger.libraries.error("Type mismatch for type: \(type) at path: \(context.codingPath)")
        case .valueNotFound(let type, let context):
          AppLogger.libraries.error("Value not found for type: \(type) at path: \(context.codingPath)")
        case .dataCorrupted(let context):
          AppLogger.libraries.error("Data corrupted at path: \(context.codingPath)")
        @unknown default:
          AppLogger.libraries.error("Unknown decoding error")
        }
      }
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch filter data: \(error.localizedDescription)"
      )
    }
  }
}
