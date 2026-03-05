import Foundation

public struct Author: Codable, Sendable {
  public let id: String
  public let name: String
  public let lastFirst: String?
  public let description: String?
  public let addedAt: Date?
  public let updatedAt: Date?
  public let numBooks: Int?
  public let imagePath: String?

  public var imageURL: URL? {
    guard imagePath != nil, let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/authors/\(id)/image")
  }
}
