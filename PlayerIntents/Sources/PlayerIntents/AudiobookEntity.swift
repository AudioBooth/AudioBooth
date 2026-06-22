import AppIntents
import Foundation
import Models

@available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@AppEntity(schema: .books.audiobook)
public struct AudiobookEntity: AppEntity {
  public struct Query: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [AudiobookEntity] {
      try await MainActor.run {
        try identifiers.compactMap { identifier in
          guard let book = try LocalBook.fetch(bookID: identifier),
            book.mediaType.contains(.audiobook)
          else {
            return nil
          }
          return AudiobookEntity(book)
        }
      }
    }

    public func entities(matching string: String) async throws -> [AudiobookEntity] {
      try await MainActor.run {
        let query = string.lowercased()
        return try LocalBook.fetchAll()
          .filter { book in
            book.mediaType.contains(.audiobook)
              && (book.title.lowercased().contains(query)
                || book.authorNames.lowercased().contains(query))
          }
          .map(AudiobookEntity.init(_:))
      }
    }

    public func suggestedEntities() async throws -> [AudiobookEntity] {
      try await MainActor.run {
        try LocalBook.fetchAll()
          .filter { $0.mediaType.contains(.audiobook) }
          .map(AudiobookEntity.init)
      }
    }
  }

  public static let defaultQuery = Query()

  public let id: String

  @Property
  public var title: String?

  @Property
  public var seriesTitle: String?

  @Property
  public var author: String?

  @Property
  public var genre: String?

  @Property
  public var purchaseDate: Date?

  @Property
  public var url: URL?

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title ?? "Audiobook")",
      subtitle: author.map { "\($0)" }
    )
  }

  public init(
    id: String,
    title: String? = nil,
    seriesTitle: String? = nil,
    author: String? = nil,
    genre: String? = nil,
    purchaseDate: Date? = nil,
    url: URL? = nil
  ) {
    self.id = id
    self.title = title
    self.seriesTitle = seriesTitle
    self.author = author
    self.genre = genre
    self.purchaseDate = purchaseDate
    self.url = url
  }

  init(_ book: LocalBook) {
    self.init(
      id: book.bookID,
      title: book.title,
      seriesTitle: book.series.first?.name,
      author: book.authorNames.isEmpty ? nil : book.authorNames,
      genre: book.genres?.first,
      purchaseDate: book.createdAt
    )
  }
}
