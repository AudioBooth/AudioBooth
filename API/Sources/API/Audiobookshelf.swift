import Foundation
import KeychainAccess
import Nuke
@_exported import NukeUI

public final class Audiobookshelf: @unchecked Sendable {
  public static let shared = Audiobookshelf()

  var networkService: NetworkService?

  public lazy var authentication = AuthenticationService(audiobookshelf: self)
  public lazy var libraries = LibrariesService(audiobookshelf: self)
  public lazy var sessions = SessionService(audiobookshelf: self)
  public lazy var books = BooksService(audiobookshelf: self)
  public lazy var podcasts = PodcastsService(audiobookshelf: self)
  public lazy var series = SeriesService(audiobookshelf: self)
  public lazy var authors = AuthorsService(audiobookshelf: self)
  public lazy var narrators = NarratorsService(audiobookshelf: self)
  public lazy var search = SearchService(audiobookshelf: self)
  public lazy var playlists = PlaylistsService(audiobookshelf: self)
  public lazy var collections = CollectionsService(audiobookshelf: self)
  public lazy var bookmarks = BookmarksService(audiobookshelf: self)
  public lazy var networkDiscovery = NetworkDiscoveryService(audiobookshelf: self)
  public lazy var misc = MiscService(audiobookshelf: self)

  public var serverURL: URL? { authentication.serverURL }
  public var isAuthenticated: Bool { authentication.isAuthenticated }

  private init() {
    setupNetworkService()

    ImagePipeline.shared = ImagePipeline {
      let configuration = DataLoader.defaultConfiguration
      configuration.urlCache = nil
      configuration.httpAdditionalHeaders = authentication.server?.customHeaders
      $0.dataLoader = DataLoader(configuration: configuration)

      $0.dataCache = try? DataCache(name: "me.jgrenier.audioBS.images")
    }
  }

  public func logout(serverID: String) {
    authentication.logout(serverID: serverID)
  }

  public func logoutAll() {
    authentication.logoutAll()
  }

  func setupNetworkService() {
    guard let server = authentication.server else {
      networkService = nil
      return
    }

    networkService = NetworkService(
      baseURL: server.baseURL,
      server: server
    ) { [weak self] in
      guard let self = self,
        let server = self.authentication.server
      else { return [:] }

      let freshToken = try? await server.freshToken
      guard let credentials = freshToken else { return [:] }

      var headers = server.customHeaders
      headers["Authorization"] = credentials.bearer
      return headers
    }
  }

  public func switchToServer(_ serverID: String) async throws {
    try authentication.switchToServer(serverID)

    guard let server = authentication.server else {
      throw AudiobookshelfError.networkError("Failed to get server after switching")
    }

    onServerSwitched?(serverID, server.baseURL)
  }

  public var onServerSwitched: ((String, URL) -> Void)?

  public enum AudiobookshelfError: Error {
    case invalidURL
    case loginFailed(String)
    case networkError(String)
    case compositionError(String)
  }
}

extension Audiobookshelf.AudiobookshelfError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL"
    case .loginFailed(let message):
      return "Login failed: \(message)"
    case .networkError(let message):
      return "Network error: \(message)"
    case .compositionError(let message):
      return "Composition error: \(message)"
    }
  }
}

public struct Page<T: Decodable & Sendable>: Decodable, Sendable {
  public let results: [T]
  public let total: Int
  public let page: Int

  public init(results: [T], total: Int, page: Int) {
    self.results = results
    self.total = total
    self.page = page
  }

  private enum CodingKeys: String, CodingKey {
    case results, authors
    case total, page
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    if let results = try container.decodeIfPresent([T].self, forKey: .results) {
      self.results = results
    } else if let authors = try container.decodeIfPresent([T].self, forKey: .authors) {
      self.results = authors
    } else {
      self.results = []
    }

    self.total = try container.decode(Int.self, forKey: .total)
    self.page = try container.decode(Int.self, forKey: .page)
  }
}
