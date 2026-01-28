import API
@preconcurrency import Foundation
import SwiftData

@Model
public final class LocalBook {
  @Attribute(.unique) public var bookID: String
  public var title: String
  public var authors: [Author]
  public var narrators: [String]
  public var series: [Series]
  public var coverURL: URL?
  public var duration: TimeInterval
  public var tracks: [Track]
  public var chapters: [Chapter]
  public var publishedYear: String?
  public var displayOrder: Int = 0
  public var createdAt: Date = Date()
  public var ebookFile: URL?

  public var authorNames: String {
    authors.map(\.name).joined(separator: ", ")
  }

  public var ebookLocalPath: URL? {
    guard let ebookFile else { return nil }

    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      return nil
    }

    let fileURL = appGroupURL.appendingPathComponent(ebookFile.relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return fileURL
  }

  public func coverURL(raw: Bool = false) -> URL? {
    guard var url = coverURL else { return nil }

    #if os(watchOS)
    url.append(queryItems: [URLQueryItem(name: "format", value: "jpg")])
    #else
    if raw {
      url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    }
    #endif

    return url
  }

  public init(
    bookID: String,
    title: String,
    authors: [Author] = [],
    narrators: [String] = [],
    series: [Series] = [],
    coverURL: URL? = nil,
    duration: TimeInterval,
    tracks: [Track] = [],
    chapters: [Chapter] = [],
    publishedYear: String? = nil,
    displayOrder: Int = 0,
    createdAt: Date = Date(),
    ebookFile: URL? = nil
  ) {
    self.bookID = bookID
    self.title = title
    self.authors = authors
    self.narrators = narrators
    self.series = series
    self.coverURL = coverURL
    self.duration = duration
    self.tracks = tracks
    self.chapters = chapters
    self.publishedYear = publishedYear
    self.displayOrder = displayOrder
    self.createdAt = createdAt
    self.ebookFile = ebookFile
  }
}

@MainActor
extension LocalBook {
  public static func fetchAll() throws -> [LocalBook] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<LocalBook>()
    return try context.fetch(descriptor)
  }

  public static func fetch(bookID: String) throws -> LocalBook? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<LocalBook> { item in
      item.bookID == bookID
    }
    let descriptor = FetchDescriptor<LocalBook>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existingItem = try LocalBook.fetch(bookID: self.bookID) {
      existingItem.title = self.title
      existingItem.authors = self.authors
      existingItem.narrators = self.narrators
      existingItem.series = self.series
      existingItem.coverURL = self.coverURL
      existingItem.duration = self.duration
      existingItem.chapters = self.chapters
      existingItem.publishedYear = self.publishedYear
      existingItem.ebookFile = self.ebookFile

      var mergedTracks: [Track] = []
      for newTrack in self.tracks {
        if let existingTrack = existingItem.tracks.first(where: { $0.index == newTrack.index }) {
          newTrack.relativePath = newTrack.relativePath ?? existingTrack.relativePath
        }
        mergedTracks.append(newTrack)
      }
      existingItem.tracks = mergedTracks
    } else {
      context.insert(self)
    }

    try context.save()
  }

  public func delete() throws {
    let context = ModelContextProvider.shared.context
    context.delete(self)
    try context.save()
  }

  public static func deleteAll() throws {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<LocalBook>()
    let allItems = try context.fetch(descriptor)

    for item in allItems {
      context.delete(item)
    }

    try context.save()
  }

  public static func updateDisplayOrders(_ bookIDsInOrder: [String]) throws {
    let context = ModelContextProvider.shared.context
    for (index, bookID) in bookIDsInOrder.enumerated() {
      if let book = try fetch(bookID: bookID) {
        book.displayOrder = index
      }
    }
    try context.save()
  }

  public func track(at time: TimeInterval) -> Track? {
    let tracks = orderedTracks
    guard !tracks.isEmpty else { return nil }

    var currentTime: TimeInterval = 0
    for track in tracks {
      if time >= currentTime && time < currentTime + track.duration {
        return track
      }
      currentTime += track.duration
    }

    return nil
  }

  public var orderedChapters: [Chapter] {
    chapters.sorted(by: { $0.start < $1.start })
  }

  public var orderedTracks: [Track] {
    tracks.sorted(by: { $0.index < $1.index })
  }

  public var isDownloaded: Bool {
    if tracks.isEmpty {
      return ebookFile != nil
    }
    return tracks.allSatisfy { track in track.relativePath != nil }
  }

  public convenience init(from book: Book) {
    let authors =
      book.media.metadata.authors?.map { apiAuthor in
        Author(id: apiAuthor.id, name: apiAuthor.name)
      } ?? []

    let series =
      book.media.metadata.series?.map { apiSeries in
        Series(id: apiSeries.id, name: apiSeries.name, sequence: apiSeries.sequence)
      } ?? []

    let narrators = book.media.metadata.narrators ?? []

    self.init(
      bookID: book.id,
      title: book.title,
      authors: authors,
      narrators: narrators,
      series: series,
      coverURL: book.coverURL(),
      duration: book.duration,
      tracks: book.tracks?.map(Track.init) ?? [],
      chapters: book.chapters?.map(Chapter.init) ?? [],
      publishedYear: book.publishedYear
    )
  }
}

extension LocalBook: Comparable {
  public static func < (lhs: LocalBook, rhs: LocalBook) -> Bool {
    if lhs.displayOrder != rhs.displayOrder {
      return lhs.displayOrder < rhs.displayOrder
    } else if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    } else {
      return lhs.title < rhs.title
    }
  }
}
