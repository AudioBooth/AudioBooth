import Foundation
import KeychainAccess
import Nuke
import OSLog

public final class AuthenticationService {
  private let audiobookshelf: Audiobookshelf
  private let keychain = Keychain(service: "me.jgrenier.AudioBS")

  public var onAuthenticationChanged: ((URL, String)?) -> Void = { _ in }

  enum Keys {
    static let connection = "audiobookshelf_server_connection"
  }

  public struct Connection: Codable {
    public let serverURL: URL
    public let token: String
    public let customHeaders: [String: String]

    public init(serverURL: URL, token: String, customHeaders: [String: String] = [:]) {
      self.serverURL = serverURL
      self.token = token
      self.customHeaders = customHeaders
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      serverURL = try container.decode(URL.self, forKey: .serverURL)
      token = try container.decode(String.self, forKey: .token)
      customHeaders =
        try container.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
    }
  }

  public var connection: Connection? {
    get {
      guard let data = try? keychain.getData(Keys.connection) else { return nil }
      return try? JSONDecoder().decode(Connection.self, from: data)
    }
    set {
      if let newValue = newValue {
        guard let data = try? JSONEncoder().encode(newValue) else { return }
        try? keychain.set(data, key: Keys.connection)
      } else {
        try? keychain.remove(Keys.connection)
      }
      audiobookshelf.setupNetworkService()
    }
  }

  public var serverURL: URL? { connection?.serverURL }
  public var isAuthenticated: Bool { connection != nil }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
    migrateKeychainIfNeeded()
  }

  private func migrateKeychainIfNeeded() {
    guard connection == nil else { return }

    let legacyKeychain = Keychain(service: "com.yourapp.audiobookshelf")

    if let data = try? legacyKeychain.getData(Keys.connection),
      let legacyConnection = try? JSONDecoder().decode(Connection.self, from: data)
    {
      connection = legacyConnection
      try? legacyKeychain.remove(Keys.connection)
      AppLogger.authentication.info("Migrated keychain from legacy storage")
      return
    }
  }

  public func login(
    serverURL: String, username: String, password: String, customHeaders: [String: String] = [:]
  ) async throws {
    guard let baseURL = URL(string: serverURL) else {
      throw Audiobookshelf.AudiobookshelfError.invalidURL
    }

    let loginService = NetworkService(baseURL: baseURL)

    struct LoginRequest: Codable {
      let username: String
      let password: String
    }

    struct Response: Codable {
      struct User: Codable {
        let token: String
      }
      let user: User
    }

    let loginRequest = LoginRequest(username: username, password: password)
    let request = NetworkRequest<Response>(
      path: "/audiobookshelf/login",
      method: .post,
      body: loginRequest
    )

    do {
      let response = try await loginService.send(request)
      let token = response.value.user.token

      self.connection = Connection(serverURL: baseURL, token: token, customHeaders: customHeaders)
      onAuthenticationChanged((baseURL, token))

    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Login failed: \(error.localizedDescription)")
    }
  }

  public func loginWithOIDC(
    serverURL: String, code: String, verifier: String, state: String?, cookies: [HTTPCookie],
    customHeaders: [String: String] = [:]
  ) async throws {
    guard let baseURL = URL(string: serverURL) else {
      throw Audiobookshelf.AudiobookshelfError.invalidURL
    }

    let loginService = NetworkService(baseURL: baseURL)

    struct Response: Codable {
      struct User: Codable {
        let token: String
      }
      let user: User
    }

    var query: [String: String] = [
      "code": code,
      "code_verifier": verifier,
    ]

    if let state {
      query["state"] = state
    }

    let headers = [
      "Cookie": cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    ]

    let request = NetworkRequest<Response>(
      path: "/auth/openid/callback",
      method: .get,
      query: query,
      headers: headers
    )

    do {
      let response = try await loginService.send(request)
      let token = response.value.user.token

      self.connection = Connection(serverURL: baseURL, token: token, customHeaders: customHeaders)
      onAuthenticationChanged((baseURL, token))
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "OIDC login failed: \(error.localizedDescription)")
    }
  }

  public func logout() {
    connection = nil
    audiobookshelf.libraries.current = nil
    ImagePipeline.shared.cache.removeAll()
    onAuthenticationChanged(nil)
  }

  public func fetchMe() async throws -> User {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
    }

    let request = NetworkRequest<User>(
      path: "/api/me",
      method: .get
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch user data: \(error.localizedDescription)")
    }
  }

  public func fetchListeningStats() async throws -> ListeningStats {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
    }

    let request = NetworkRequest<ListeningStats>(
      path: "/api/me/listening-stats",
      method: .get
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch listening stats: \(error.localizedDescription)")
    }
  }
}
