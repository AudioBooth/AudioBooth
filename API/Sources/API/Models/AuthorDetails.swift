import Foundation

public struct AuthorDetails: Codable, Sendable {
  public let id: String
  public let asin: String?
  public let name: String
  public let description: String?
  public let imagePath: String?
  public let libraryID: String
  public let addedAt: Date
  public let updatedAt: Date
  public let series: [SeriesWithItems]
  public let libraryItems: [Book]

  @MainActor
  public var imageURL: URL? {
    guard imagePath != nil, let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    return serverURL.appendingPathComponent("api/authors/\(id)/image")
  }

  public struct SeriesWithItems: Codable, Sendable {
    public let id: String
    public let name: String
    public let items: [Book]
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case asin
    case name
    case description
    case imagePath
    case libraryID = "libraryId"
    case addedAt
    case updatedAt
    case series
    case libraryItems
  }
}
