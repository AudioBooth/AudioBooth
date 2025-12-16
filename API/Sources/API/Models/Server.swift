import Combine
import Foundation

@Observable
public final class Server: @unchecked Sendable {
  public let id: String
  public let baseURL: URL
  public internal(set) var token: Credentials
  public internal(set) var customHeaders: [String: String]
  public internal(set) var alias: String?

  public enum Status {
    case connected
    case connectionError
    case authenticationError
  }

  public var status: Status = .connected

  @ObservationIgnored
  private lazy var credentialsActor = CredentialsActor(server: self)

  public var freshToken: Credentials {
    get async throws {
      try await credentialsActor.freshCredentials
    }
  }

  public init(connection: Connection) {
    self.id = connection.id
    self.baseURL = connection.serverURL
    self.token = connection.token
    self.customHeaders = connection.customHeaders
    self.alias = connection.alias
  }
}
