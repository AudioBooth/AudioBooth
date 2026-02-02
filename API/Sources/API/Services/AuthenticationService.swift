import Foundation
import KeychainAccess
import Logging
import Nuke

public final class AuthenticationService: ObservableObject {
  private let audiobookshelf: Audiobookshelf
  private let keychain = Keychain(service: "me.jgrenier.AudioBS")

  enum Keys {
    static let connections = "audiobookshelf_server_connections"
    static let activeServerID = "audiobookshelf_active_server_id"
    static let permissions = "audiobookshelf_user_permissions"
  }

  private var connections: [String: Connection] = [:] {
    didSet {
      if !connections.isEmpty {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? keychain.set(data, key: Keys.connections)
      } else {
        try? keychain.remove(Keys.connections)
      }
    }
  }

  public var servers: [String: Server] = [:]

  public private(set) var server: Server? {
    didSet {
      if let server {
        UserDefaults.standard.set(server.id, forKey: Keys.activeServerID)
      } else {
        UserDefaults.standard.removeObject(forKey: Keys.activeServerID)
      }
      audiobookshelf.setupNetworkService()
    }
  }

  public var serverURL: URL? { server?.baseURL }
  public var isAuthenticated: Bool { server != nil }

  public var permissions: User.Permissions? {
    get {
      guard let data = UserDefaults.standard.data(forKey: Keys.permissions) else { return nil }
      return try? JSONDecoder().decode(User.Permissions.self, from: data)
    }
    set {
      if let newValue {
        guard let data = try? JSONEncoder().encode(newValue) else { return }
        UserDefaults.standard.set(data, forKey: Keys.permissions)
      } else {
        UserDefaults.standard.removeObject(forKey: Keys.permissions)
      }
    }
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf

    migrateLegacyConnection()

    if connections.isEmpty,
      let data = try? keychain.getData(Keys.connections),
      let decoded = try? JSONDecoder().decode([String: Connection].self, from: data)
    {
      self.connections = decoded
      self.servers = decoded.mapValues { Server(connection: $0) }

      if let activeServerID = UserDefaults.standard.string(forKey: Keys.activeServerID) {
        self.server = servers[activeServerID]
      }
    }
  }

  public func migrateLegacyConnection() {
    struct LegacyConnection: Codable {
      let serverURL: URL
      let token: String
      let customHeaders: [String: String]?
      let alias: String?
    }

    let legacyConnectionKey = "audiobookshelf_server_connection"

    guard let legacyData = try? keychain.getData(legacyConnectionKey) else {
      return
    }

    guard let legacyConnection = try? JSONDecoder().decode(LegacyConnection.self, from: legacyData)
    else {
      AppLogger.authentication.error("Failed to decode legacy connection")
      return
    }

    AppLogger.authentication.info("Migrating legacy connection to multi-server format")

    do {
      try keychain.remove(legacyConnectionKey)
    } catch {
      AppLogger.authentication.error("Failed to remove legacy key: \(error.localizedDescription)")
      return
    }

    let connection = Connection(
      serverURL: legacyConnection.serverURL,
      token: .legacy(token: legacyConnection.token),
      customHeaders: legacyConnection.customHeaders ?? [:],
      alias: legacyConnection.alias
    )

    self.connections = [connection.id: connection]
    self.servers = [connection.id: Server(connection: connection)]
    self.server = servers.first?.value
  }

  public func login(
    serverURL: String,
    username: String,
    password: String,
    customHeaders: [String: String] = [:],
    existingServerID: String? = nil
  ) async throws -> String {
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
        let token: String?
        let accessToken: String?
        let refreshToken: String?
      }
      let user: User
    }

    let loginRequest = LoginRequest(username: username, password: password)
    var headers = customHeaders
    headers["x-return-tokens"] = "true"

    let request = NetworkRequest<Response>(
      path: "/login",
      method: .post,
      body: loginRequest,
      headers: headers
    )

    let response = try await loginService.send(request)
    let user = response.value.user

    let authToken: Credentials
    if let accessToken = user.accessToken, let refreshToken = user.refreshToken {
      guard let expiresAt = JWT(accessToken)?.exp else {
        throw Audiobookshelf.AudiobookshelfError.loginFailed("Failed to decode JWT token")
      }
      authToken = .bearer(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt
      )
    } else if let token = user.token {
      authToken = .legacy(token: token)
    } else {
      throw Audiobookshelf.AudiobookshelfError.loginFailed("No token received from server")
    }

    return try upsertConnection(
      serverURL: baseURL,
      token: authToken,
      customHeaders: customHeaders,
      existingServerID: existingServerID
    )
  }

  public func loginWithOIDC(
    serverURL: String,
    code: String,
    verifier: String,
    state: String?,
    cookies: [HTTPCookie],
    customHeaders: [String: String] = [:],
    existingServerID: String? = nil
  ) async throws -> String {
    AppLogger.authentication.info("loginWithOIDC called for server: \(serverURL)")
    AppLogger.authentication.debug(
      "Request parameters - code length: \(code.count), verifier length: \(verifier.count), state: \(state ?? "nil"), cookies: \(cookies.count), custom headers: \(customHeaders.count)"
    )

    guard let baseURL = URL(string: serverURL) else {
      AppLogger.authentication.error("Invalid server URL: \(serverURL)")
      throw Audiobookshelf.AudiobookshelfError.invalidURL
    }

    let loginService = NetworkService(baseURL: baseURL)

    struct Response: Codable {
      struct User: Codable {
        let token: String?
        let accessToken: String?
        let refreshToken: String?
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

    var headers = customHeaders
    headers["Cookie"] = cookieString
    headers["x-return-tokens"] = "true"

    AppLogger.authentication.info("Sending OIDC callback request to /auth/openid/callback")
    AppLogger.authentication.debug(
      "Query parameters: \(query.keys.joined(separator: ", "))"
    )
    AppLogger.authentication.debug("Cookie header: \(cookieString)")

    let request = NetworkRequest<Response>(
      path: "/auth/openid/callback",
      method: .get,
      query: query,
      headers: headers
    )

    do {
      let response = try await loginService.send(request)
      let user = response.value.user

      let authToken: Credentials
      if let accessToken = user.accessToken, let refreshToken = user.refreshToken {
        guard let expiresAt = JWT(accessToken)?.exp else {
          throw Audiobookshelf.AudiobookshelfError.loginFailed("Failed to decode JWT token")
        }
        authToken = .bearer(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: expiresAt
        )
        AppLogger.authentication.info("OIDC login successful, received JWT tokens")
      } else if let token = user.token {
        authToken = .legacy(token: token)
        AppLogger.authentication.info(
          "OIDC login successful, received legacy token of length: \(token.count)"
        )
      } else {
        throw Audiobookshelf.AudiobookshelfError.loginFailed("No token received from server")
      }

      return try upsertConnection(
        serverURL: baseURL,
        token: authToken,
        customHeaders: customHeaders,
        existingServerID: existingServerID
      )
    } catch {
      AppLogger.authentication.error(
        "OIDC login request failed: \(error.localizedDescription)"
      )
      if let error = error as? URLError {
        AppLogger.authentication.error("URLError code: \(error.code.rawValue)")
      }
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "OIDC login failed: \(error.localizedDescription)"
      )
    }
  }

  public func switchToServer(_ serverID: String) throws {
    guard let newServer = servers[serverID] else {
      throw Audiobookshelf.AudiobookshelfError.networkError("Server not found")
    }
    server = newServer
  }

  public func restoreConnection(_ connection: Connection) {
    connections[connection.id] = connection

    let restoredServer = Server(connection: connection)
    servers[connection.id] = restoredServer
    server = restoredServer
  }

  public func updateAlias(_ serverID: String, alias: String?) {
    guard let server = servers[serverID] else { return }

    server.alias = alias

    connections[serverID] = Connection(server)
  }

  public func updateCustomHeaders(_ serverID: String, customHeaders: [String: String]) {
    guard let server = servers[serverID] else { return }

    server.customHeaders = customHeaders

    ImagePipeline.shared = ImagePipeline {
      let configuration = DataLoader.defaultConfiguration
      configuration.requestCachePolicy = .returnCacheDataElseLoad
      configuration.httpAdditionalHeaders = customHeaders
      $0.dataLoader = DataLoader(configuration: configuration)
    }

    var allConnections = connections
    allConnections[serverID] = Connection(server)
    connections = allConnections
  }

  public func updateToken(_ serverID: String, token: Credentials) {
    guard let server = servers[serverID] else { return }

    server.token = token

    connections[serverID] = Connection(server)
  }

  public func removeServer(_ serverID: String) {
    var allConnections = connections
    allConnections.removeValue(forKey: serverID)
    connections = allConnections

    servers.removeValue(forKey: serverID)

    if server?.id == serverID {
      server = nil
    }
  }

  private func upsertConnection(
    serverURL: URL,
    token: Credentials,
    customHeaders: [String: String],
    existingServerID: String?
  ) throws -> String {
    if let existingServerID {
      guard let existingServer = servers[existingServerID] else {
        throw Audiobookshelf.AudiobookshelfError.networkError("Server not found")
      }

      existingServer.token = token

      let updatedConnection = Connection(
        id: existingServerID,
        serverURL: serverURL,
        token: token,
        customHeaders: customHeaders,
        alias: existingServer.alias
      )

      var allConnections = connections
      allConnections[existingServerID] = updatedConnection
      connections = allConnections

      return existingServerID
    } else {
      let newConnection = Connection(
        serverURL: serverURL,
        token: token,
        customHeaders: customHeaders
      )
      let newServer = Server(connection: newConnection)

      var allConnections = connections
      allConnections[newConnection.id] = newConnection
      connections = allConnections

      servers[newConnection.id] = newServer

      return newConnection.id
    }
  }

  public func logout(serverID: String) {
    if server?.id == serverID {
      permissions = nil
      audiobookshelf.libraries.current = nil
      ImagePipeline.shared.cache.removeAll()
    }
    removeServer(serverID)
  }

  public func logoutAll() {
    connections = [:]
    servers = [:]
    server = nil
    permissions = nil
    audiobookshelf.libraries.current = nil
    ImagePipeline.shared.cache.removeAll()
  }

  public func authorize() async throws -> Authorize {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Authorize>(
      path: "/api/authorize",
      method: .post,
      body: nil
    )

    do {
      let response = try await networkService.send(request)
      let authorize = response.value
      permissions = authorize.user.permissions
      audiobookshelf.misc.ereaderDevices = authorize.ereaderDevices
      audiobookshelf.libraries.sortingIgnorePrefix = authorize.serverSettings.sortingIgnorePrefix
      return authorize
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch user data: \(error.localizedDescription)"
      )
    }
  }

  public func fetchMe() async throws -> User {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
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
        "Failed to fetch user data: \(error.localizedDescription)"
      )
    }
  }

  public func fetchListeningStats() async throws -> ListeningStats {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
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
        "Failed to fetch listening stats: \(error.localizedDescription)"
      )
    }
  }

  public func fetchYearStats(year: Int) async throws -> YearStats {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<YearStats>(
      path: "/api/me/stats/year/\(year)",
      method: .get
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch year stats: \(error.localizedDescription)"
      )
    }
  }

  func refreshToken(for server: Server) async throws -> Credentials {
    guard case .bearer(_, let refreshToken, _) = server.token else {
      throw Audiobookshelf.AudiobookshelfError.loginFailed("Token not in correct format")
    }

    struct Response: Codable {
      struct User: Codable {
        let accessToken: String
        let refreshToken: String
      }
      let user: User
    }

    let networkService = NetworkService(baseURL: server.baseURL)

    var headers = server.customHeaders
    headers["x-refresh-token"] = refreshToken

    let request = NetworkRequest<Response>(
      path: "/auth/refresh",
      method: .post,
      body: nil,
      headers: headers
    )

    let response = try await networkService.send(request)
    let user = response.value.user

    guard let newExpiresAt = JWT(user.accessToken)?.exp else {
      throw Audiobookshelf.AudiobookshelfError.loginFailed("Failed to decode refreshed JWT token")
    }

    let newToken = Credentials.bearer(
      accessToken: user.accessToken,
      refreshToken: user.refreshToken,
      expiresAt: newExpiresAt
    )

    server.token = newToken
    updateToken(server.id, token: newToken)

    return newToken
  }

  public func checkServersHealth() async {
    let activeServerID = server?.id

    for (serverID, _) in servers where serverID != activeServerID {
      _ = try? await self.audiobookshelf.libraries.fetch(serverID: serverID)
    }
  }
}
