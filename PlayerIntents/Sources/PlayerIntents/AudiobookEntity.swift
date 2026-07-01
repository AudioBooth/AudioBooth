import AppIntents
import Foundation
import Models

@available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@AppEntity(schema: .books.audiobook)
public struct AudiobookEntity: AppEntity, IndexedEntity, PersistentlyIdentifiable {
  public struct Query: EntityStringQuery, EnumerableEntityQuery {
    public init() {}

    public func allEntities() async throws -> [AudiobookEntity] {
      await Self.localAudiobooks(matching: nil)
    }

    public func entities(for identifiers: [String]) async throws -> [AudiobookEntity] {
      var entities: [AudiobookEntity] = []
      for identifier in identifiers {
        if let local = await Self.localAudiobook(id: identifier) {
          entities.append(local)
        }
      }
      return entities
    }

    public func entities(matching string: String) async throws -> [AudiobookEntity] {
      await Self.localAudiobooks(matching: string)
    }

    public func suggestedEntities() async throws -> [AudiobookEntity] {
      await Self.localAudiobooks(matching: nil)
    }

    @MainActor
    private static func localAudiobook(id: String) -> AudiobookEntity? {
      guard let book = try? LocalBook.fetch(bookID: id), book.mediaType.contains(.audiobook) else {
        return nil
      }
      return AudiobookEntity(book)
    }

    @MainActor
    private static func localAudiobooks(matching query: String?) -> [AudiobookEntity] {
      let query = query?.lowercased()
      return ((try? LocalBook.fetchAll()) ?? [])
        .filter { book in
          guard book.mediaType.contains(.audiobook) else { return false }
          guard let query, !query.isEmpty else { return true }
          return book.title.lowercased().contains(query)
            || book.authorNames.lowercased().contains(query)
        }
        .map(AudiobookEntity.init)
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

@available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct AudiobookEntityOptionsProvider: DynamicOptionsProvider {
  public init() {}

  public func results() async throws -> [AudiobookEntity] {
    try await AudiobookEntity.Query().suggestedEntities()
  }
}
