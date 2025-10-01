import Foundation
import KeychainAccess
import Nuke

public final class AuthenticationService {
  private let audiobookshelf: Audiobookshelf
  private let keychain = Keychain(
    service: "me.jgrenier.AudioBS", accessGroup: "7MM2M9KD2W.me.jgrenier.AudioBS"
  ).synchronizable(true)

  enum Keys {
    static let connection = "audiobookshelf_server_connection"
  }

  struct Connection: Codable {
    let serverURL: URL
    let token: String
  }
  private(set) var connection: Connection? {
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
      print("Migrated keychain from legacy storage")
      return
    }
  }

  public func login(serverURL: String, username: String, password: String) async throws {
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

      self.connection = Connection(serverURL: baseURL, token: token)
      audiobookshelf.setupNetworkService()

    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Login failed: \(error.localizedDescription)")
    }
  }

  public func loginWithOIDC(
    serverURL: String, code: String, verifier: String, state: String?, cookies: [HTTPCookie]
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

      self.connection = Connection(serverURL: baseURL, token: token)
      audiobookshelf.setupNetworkService()
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "OIDC login failed: \(error.localizedDescription)")
    }
  }

  public func logout() {
    connection = nil
    audiobookshelf.libraries.current = nil
    audiobookshelf.setupNetworkService()
    ImagePipeline.shared.cache.removeAll()
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
}
