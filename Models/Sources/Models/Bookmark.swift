import API
import CoreData
@preconcurrency import Foundation
import SwiftData

@Model
public final class Bookmark {
  public enum Status: String, Codable {
    case pending
    case synced
    case failed
  }

  public enum Error: Swift.Error {
    case notFound
    case saveFailed
    case syncFailed(Swift.Error)
  }

  public var bookID: String
  public var time: Int
  public var title: String
  public var createdAt: Date
  public var status: Status = Status.synced

  public init(
    bookID: String,
    time: Int,
    title: String,
    createdAt: Date = Date(),
    status: Status = .pending
  ) {
    self.bookID = bookID
    self.time = time
    self.title = title
    self.createdAt = createdAt
    self.status = status
  }

  public convenience init(from apiBookmark: User.Bookmark) {
    self.init(
      bookID: apiBookmark.bookID,
      time: Int(apiBookmark.time),
      title: apiBookmark.title,
      createdAt: Date(timeIntervalSince1970: TimeInterval(apiBookmark.createdAt / 1000)),
      status: .synced
    )
  }
}

@MainActor
extension Bookmark {
  public static func fetchAll() throws -> [Bookmark] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<Bookmark>(
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    let results = try context.fetch(descriptor)
    return results
  }

  public static func fetch(bookID: String) throws -> [Bookmark] {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<Bookmark> { bookmark in
      bookmark.bookID == bookID
    }
    let descriptor = FetchDescriptor<Bookmark>(
      predicate: predicate,
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    let results = try context.fetch(descriptor)
    return results
  }

  public static func fetch(bookID: String, time: Int) throws -> Bookmark? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<Bookmark> { bookmark in
      bookmark.bookID == bookID && bookmark.time == time
    }
    let descriptor = FetchDescriptor<Bookmark>(predicate: predicate)
    let results = try context.fetch(descriptor)
    return results.first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existingBookmark = try Bookmark.fetch(bookID: self.bookID, time: self.time) {
      existingBookmark.title = self.title
      existingBookmark.createdAt = self.createdAt
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
    let descriptor = FetchDescriptor<Bookmark>()
    let allBookmarks = try context.fetch(descriptor)

    for bookmark in allBookmarks {
      context.delete(bookmark)
    }

    try context.save()
  }

  public static func syncFromAPI(userData: User) throws {
    let context = ModelContextProvider.shared.context

    for apiBookmark in userData.bookmarks {
      let remote = Bookmark(from: apiBookmark)

      if let local = try Bookmark.fetch(bookID: apiBookmark.bookID, time: Int(apiBookmark.time)) {
        local.title = remote.title
        local.createdAt = remote.createdAt
        local.status = .synced
      } else {
        context.insert(remote)
      }
    }

    try context.save()
  }
}
