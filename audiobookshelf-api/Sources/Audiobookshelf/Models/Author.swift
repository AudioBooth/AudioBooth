import Foundation

public struct Author: Codable, Sendable {
  public let id: String
  public let name: String
  public let description: String?
  public let addedAt: Int?
  public let updatedAt: Int?
  public let numBooks: Int?

  public var imageURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/authors/\(id)/image")
  }
}
