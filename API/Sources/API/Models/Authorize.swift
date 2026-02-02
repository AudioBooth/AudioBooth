import Foundation

public struct Authorize: Codable, Sendable {
  public let user: User
  public let userDefaultLibraryId: String
  public let ereaderDevices: [EreaderDevice]
  public let serverSettings: ServerSettings
}

public struct ServerSettings: Codable, Sendable {
  public let id: String
  public let version: String
  public let sortingIgnorePrefix: Bool
}

public struct EreaderDevice: Codable, Sendable {
  public let name: String
}
