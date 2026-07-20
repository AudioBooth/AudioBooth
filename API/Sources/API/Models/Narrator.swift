import Foundation

public struct Narrator: Codable, Sendable {
  public let id: String
  public let name: String
  public let numBooks: Int?

  @MainActor
  public var imageURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/narrators/\(id)/image")
  }
}
