import Combine
import Foundation

@Observable
public final class Server: @unchecked Sendable {
  public let id: String
  public let baseURL: URL
  public internal(set) var token: Credentials
  public internal(set) var customHeaders: [String: String]
  public internal(set) var alias: String?
  public internal(set) var alternativeURL: URL?
  public var urlMode: URLMode

  public enum URLMode {
    case primary
    case alternative
    case fallback
  }

  public var isUsingAlternativeURL: Bool {
    urlMode == .alternative || urlMode == .fallback
  }

  public var activeURL: URL {
    isUsingAlternativeURL ? alternativeURL ?? baseURL : baseURL
  }

  public enum Status {
    case connected
    case connectionError
    case authenticationError
  }

  public var status: Status = .connected

  public var canAttemptRefresh: Bool {
    if case .bearer(_, let refreshToken, _) = token {
      return !refreshToken.isEmpty
    }
    return false
  }

  func expireAccessToken() {
    guard case .bearer(let accessToken, let refreshToken, _) = token else { return }
    token = .bearer(accessToken: accessToken, refreshToken: refreshToken, expiresAt: 0)
  }

  @ObservationIgnored
  private lazy var credentialsActor = CredentialsActor(server: self)

  public var freshToken: Credentials {
    get async throws {
      try await credentialsActor.freshCredentials
    }
  }

  public let storage: UserDefaults

  @ObservationIgnored @Stored("username") public var username: String? = nil
  @ObservationIgnored @Stored("permissions") public var permissions: User.Permissions? = nil
  @ObservationIgnored @Stored("userType") public var userType: UserType? = nil
  @ObservationIgnored @Stored("defaultLibraryID") public var defaultLibraryID: String? = nil
  @ObservationIgnored @Stored("ereaderDevices") public var ereaderDevices: [EreaderDevice] = []
  @ObservationIgnored @Stored("sortingIgnorePrefix") public var sortingIgnorePrefix: Bool = false
  @ObservationIgnored @Stored("serverVersion") public var serverVersion: String? = nil

  public func clearStorage() {
    storage.removePersistentDomain(forName: "connection.\(id)")
  }

  public func update(with authorize: Authorize) {
    status = .connected
    permissions = authorize.user.permissions
    username = authorize.user.username
    userType = authorize.user.type
    defaultLibraryID = authorize.userDefaultLibraryId
    ereaderDevices = authorize.ereaderDevices
    sortingIgnorePrefix = authorize.serverSettings.sortingIgnorePrefix
    serverVersion = authorize.serverSettings.version
  }

  public init(connection: Connection) {
    self.id = connection.id
    self.baseURL = connection.serverURL
    self.token = connection.token
    self.customHeaders = connection.customHeaders
    self.alias = connection.alias
    self.alternativeURL = connection.alternativeURL
    self.urlMode = connection.isUsingAlternativeURL ? .alternative : .primary
    self.storage = UserDefaults(suiteName: "connection.\(connection.id)") ?? .standard
  }
}

extension Server {
  @propertyWrapper
  public struct Stored<Value: Codable> {
    let key: String
    let defaultValue: Value

    public init(wrappedValue: Value, _ key: String) {
      self.key = key
      self.defaultValue = wrappedValue
    }

    @available(*, unavailable, message: "@Server.Stored is only usable on Server")
    public var wrappedValue: Value {
      get { fatalError() }
      set { fatalError() }
    }

    public static subscript(
      _enclosingInstance instance: Server,
      wrapped wrappedKeyPath: ReferenceWritableKeyPath<Server, Value>,
      storage storageKeyPath: ReferenceWritableKeyPath<Server, Stored<Value>>
    ) -> Value {
      get {
        let wrapper = instance[keyPath: storageKeyPath]
        guard let data = instance.storage.data(forKey: wrapper.key),
          let value = try? JSONDecoder().decode(Value.self, from: data)
        else { return wrapper.defaultValue }
        return value
      }
      set {
        let wrapper = instance[keyPath: storageKeyPath]
        if let data = try? JSONEncoder().encode(newValue) {
          instance.storage.set(data, forKey: wrapper.key)
        }
      }
    }
  }
}
