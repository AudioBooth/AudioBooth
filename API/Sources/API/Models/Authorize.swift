import Foundation

public struct Authorize: Codable, Sendable {
  public let user: User
  public let userDefaultLibraryId: String
  public let ereaderDevices: [EreaderDevice]
}

public struct EreaderDevice: Codable, Sendable {
  public let name: String
}
