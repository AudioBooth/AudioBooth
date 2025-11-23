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
    static let permissions = "audiobookshelf_user_permissions"
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

  public var permissions: User.Permissions? {
    get {
      guard let data = UserDefaults.standard.data(forKey: Keys.permissions) else { return nil }
      return try? JSONDecoder().decode(User.Permissions.self, from: data)
    }
    set {
      if let newValue = newValue {
        guard let data = try? JSONEncoder().encode(newValue) else { return }
        UserDefaults.standard.set(data, forKey: Keys.permissions)
      } else {
        UserDefaults.standard.removeObject(forKey: Keys.permissions)
      }
    }
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func login(
    serverURL: String,
    username: String,
    password: String,
    customHeaders: [String: String] = [:]
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
      path: "/login",
      method: .post,
      body: loginRequest,
      headers: customHeaders
    )

    let response = try await loginService.send(request)
    let token = response.value.user.token

    self.connection = Connection(serverURL: baseURL, token: token, customHeaders: customHeaders)
    onAuthenticationChanged((baseURL, token))
  }

  public func loginWithOIDC(
    serverURL: String, code: String, verifier: String, state: String?, cookies: [HTTPCookie],
    customHeaders: [String: String] = [:]
  ) async throws {
    AppLogger.authentication.info("loginWithOIDC called for server: \(serverURL, privacy: .public)")
    AppLogger.authentication.debug(
      "Request parameters - code length: \(code.count), verifier length: \(verifier.count), state: \(state ?? "nil"), cookies: \(cookies.count), custom headers: \(customHeaders.count)"
    )

    guard let baseURL = URL(string: serverURL) else {
      AppLogger.authentication.error("Invalid server URL: \(serverURL, privacy: .public)")
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

    let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    let headers = [
      "Cookie": cookieString
    ]

    AppLogger.authentication.info("Sending OIDC callback request to /auth/openid/callback")
    AppLogger.authentication.debug(
      "Query parameters: \(query.keys.joined(separator: ", "), privacy: .public)")
    AppLogger.authentication.debug("Cookie header: \(cookieString, privacy: .public)")

    let request = NetworkRequest<Response>(
      path: "/auth/openid/callback",
      method: .get,
      query: query,
      headers: headers
    )

    do {
      let response = try await loginService.send(request)
      let token = response.value.user.token

      AppLogger.authentication.info(
        "OIDC login successful, received token of length: \(token.count, privacy: .public)")

      self.connection = Connection(serverURL: baseURL, token: token, customHeaders: customHeaders)
      onAuthenticationChanged((baseURL, token))
    } catch {
      AppLogger.authentication.error(
        "OIDC login request failed: \(error.localizedDescription, privacy: .public)")
      if let error = error as? URLError {
        AppLogger.authentication.error("URLError code: \(error.code.rawValue, privacy: .public)")
      }
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "OIDC login failed: \(error.localizedDescription)")
    }
  }

  public func logout() {
    connection = nil
    permissions = nil
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
      let user = response.value
      permissions = user.permissions
      return user
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
