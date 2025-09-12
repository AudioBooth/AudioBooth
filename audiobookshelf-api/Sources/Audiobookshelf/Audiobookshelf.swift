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
  public lazy var series = SeriesService(audiobookshelf: self)
  public lazy var authors = AuthorsService(audiobookshelf: self)
  public lazy var search = SearchService(audiobookshelf: self)
  public lazy var networkDiscovery = NetworkDiscoveryService(audiobookshelf: self)

  public var serverURL: URL? { authentication.serverURL }
  public var isAuthenticated: Bool { authentication.isAuthenticated }

  private init() {
    setupNetworkService()

    var configuration = ImagePipeline.Configuration.withDataCache
    configuration.dataCachePolicy = .storeAll

    let dataLoader = DataLoader()
    dataLoader.session.configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.dataLoader = dataLoader

    ImagePipeline.shared = ImagePipeline(configuration: configuration)
  }

  public func logout() {
    authentication.logout()
  }

  func setupNetworkService() {
    guard let connection = authentication.connection else {
      networkService = nil
      return
    }

    networkService = NetworkService(baseURL: connection.serverURL) { configuration in
      configuration.httpAdditionalHeaders = [
        "Authorization": "Bearer \(connection.token)"
      ]
    }
  }

  public enum AudiobookshelfError: Error {
    case invalidURL
    case loginFailed(String)
    case networkError(String)
    case compositionError(String)
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
