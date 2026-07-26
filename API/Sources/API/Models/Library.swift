import Foundation

public struct Library: Codable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let mediaType: MediaType
  public internal(set) var serverID: String

  public enum MediaType: String, Codable, Sendable, Equatable {
    case book
    case podcast
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case mediaType
    case serverID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .book
    serverID = try container.decodeIfPresent(String.self, forKey: .serverID) ?? ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(mediaType, forKey: .mediaType)
    try container.encode(serverID, forKey: .serverID)
  }
}
