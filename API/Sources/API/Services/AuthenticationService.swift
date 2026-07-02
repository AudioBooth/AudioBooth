import Foundation
import Logging
import Nuke
import SimpleKeychain

public final class AuthenticationService: ObservableObject {
  private let audiobookshelf: Audiobookshelf
  private let keychain = SimpleKeychain(service: "me.jgrenier.AudioBS")

  enum Keys {
    static let connections = "audiobookshelf_server_connections"
    static let activeServerID = "audiobookshelf_active_server_id"
  }

  private var connections: [String: Connection] = [:] {
    didSet {
      if !connections.isEmpty {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? keychain.set(data, forKey: Keys.connections)
      } else {
        try? keychain.deleteItem(forKey: Keys.connections)
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

  public var serverURL: URL? { server?.activeURL }
  public var isAuthenticated: Bool { server != nil }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf

    if let data = try? keychain.data(forKey: Keys.connections),
      let decoded = try? JSONDecoder().decode([String: Connection].self, from: data)
    {
      self.connections = decoded
      self.servers = decoded.mapValues { Server(connection: $0) }

      if let activeServerID = UserDefaults.standard.string(forKey: Keys.activeServerID) {
        self.server = servers[activeServerID]
      }
    }
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

    let loginRequest = LoginRequest(username: username, password: password)
    var headers = customHeaders
    headers["x-return-tokens"] = "true"

    let request = NetworkRequest<Authorize>(
      path: "/login",
      method: .post,
      body: loginRequest,
      headers: headers
    )

    let response = try await loginService.send(request)
    guard let authToken = response.value.user.credentials else {
      throw Audiobookshelf.AudiobookshelfError.loginFailed("No token received from server")
    }

    let connectionID = try upsertConnection(
      serverURL: baseURL,
      token: authToken,
      customHeaders: customHeaders,
      existingServerID: existingServerID
    )
    servers[connectionID]?.update(with: response.value)
    return connectionID
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

    let request = NetworkRequest<Authorize>(
      path: "/auth/openid/callback",
      method: .get,
      query: query,
      headers: headers
    )

    do {
      let response = try await loginService.send(request)
      guard let authToken = response.value.user.credentials else {
        throw Audiobookshelf.AudiobookshelfError.loginFailed("No token received from server")
      }
      AppLogger.authentication.info("OIDC login successful")

      let connectionID = try upsertConnection(
        serverURL: baseURL,
        token: authToken,
        customHeaders: customHeaders,
        existingServerID: existingServerID
      )
      servers[connectionID]?.update(with: response.value)
      return connectionID
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

  public func verifyAlternativeURL(_ url: URL, for serverID: String) async throws {
    guard let server = servers[serverID] else {
      throw Audiobookshelf.AudiobookshelfError.networkError("Server not found")
    }

    let request = NetworkRequest<Authorize>(path: "/api/authorize", method: .post, body: nil)

    let altService = NetworkService(baseURL: url, server: server) {
      let freshToken = try? await server.freshToken
      guard let credentials = freshToken else { return [:] }
      var headers = server.customHeaders
      headers["Authorization"] = credentials.bearer
      return headers
    }

    _ = try await altService.send(request)
  }

  public func updateAlternativeURL(_ serverID: String, url: URL?) {
    guard let server = servers[serverID] else { return }
    server.alternativeURL = url
    connections[serverID] = Connection(server)
  }

  public func setUsingAlternativeURL(_ serverID: String, isUsing: Bool) {
    guard let server = servers[serverID] else { return }
    server.urlMode = isUsing ? .alternative : .primary
    connections[serverID] = Connection(server)
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
    servers[serverID]?.clearStorage()

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
      audiobookshelf.libraries.current = nil
      ImagePipeline.shared.cache.removeAll()
    }
    audiobookshelf.libraries.clearAllCaches()
    removeServer(serverID)
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
      server?.update(with: authorize)
      return authorize
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch user data: \(error.localizedDescription)"
      )
    }
  }

  public func fetchListeningHistory(page: Int, itemsPerPage: Int) async throws -> ListeningHistoryResponse {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<ListeningHistoryResponse>(
      path: "/api/me/listening-sessions",
      method: .get,
      query: [
        "page": String(page),
        "itemsPerPage": String(itemsPerPage),
      ]
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch listening history: \(error.localizedDescription)"
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

  public func loginWithAPIKey(
    serverURL: String,
    apiKey: String,
    customHeaders: [String: String] = [:],
    existingServerID: String? = nil
  ) async throws -> String {
    guard let baseURL = URL(string: serverURL) else {
      throw Audiobookshelf.AudiobookshelfError.invalidURL
    }

    let token = Credentials.apiKey(key: apiKey)
    var headers = customHeaders
    headers["Authorization"] = token.bearer

    let validateService = NetworkService(baseURL: baseURL)
    let request = NetworkRequest<Authorize>(
      path: "/api/authorize",
      method: .post,
      headers: headers
    )

    let response = try await validateService.send(request)

    let connectionID = try upsertConnection(
      serverURL: baseURL,
      token: token,
      customHeaders: customHeaders,
      existingServerID: existingServerID
    )
    servers[connectionID]?.update(with: response.value)
    return connectionID
  }

  public func loginWithJWT(
    serverURL: URL,
    token: String,
    customHeaders: [String: String] = [:],
    alias: String? = nil
  ) async throws -> String {
    switch JWT(token)?.type {
    case .api:
      let connectionID = try await loginWithAPIKey(
        serverURL: serverURL.absoluteString,
        apiKey: token,
        customHeaders: customHeaders
      )
      updateAlias(connectionID, alias: alias)
      try switchToServer(connectionID)
      return connectionID

    case .refresh:
      let connection = Connection(
        serverURL: serverURL,
        token: .bearer(accessToken: "", refreshToken: token, expiresAt: 0),
        customHeaders: customHeaders,
        alias: alias
      )
      let server = Server(connection: connection)

      _ = try await refreshToken(for: server)

      restoreConnection(Connection(server))
      return connection.id

    case .access, .unknown, nil:
      throw Audiobookshelf.AudiobookshelfError.loginFailed("Unsupported token type")
    }
  }

  func refreshToken(for server: Server) async throws -> Credentials {
    if case .apiKey = server.token {
      return server.token
    }

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

    let networkService = NetworkService(baseURL: server.activeURL)

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
    for (serverID, _) in servers {
      _ = try? await self.audiobookshelf.libraries.fetch(serverID: serverID)
    }
  }
}
