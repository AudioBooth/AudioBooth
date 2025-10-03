@preconcurrency import Foundation
import SwiftData

@Model
public final class RecentlyPlayedItem {
  @Attribute(.unique) public var bookID: String
  public var title: String
  public var author: String?
  public var coverURL: URL?
  public var playSessionInfo: PlaySessionInfo

  public init(
    bookID: String,
    title: String,
    author: String? = nil,
    coverURL: URL? = nil,
    playSessionInfo: PlaySessionInfo
  ) {
    self.bookID = bookID
    self.title = title
    self.author = author
    self.coverURL = coverURL
    self.playSessionInfo = playSessionInfo
  }
}

@MainActor
extension RecentlyPlayedItem {
  public static func fetchAll() throws -> [RecentlyPlayedItem] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<RecentlyPlayedItem>()
    return try context.fetch(descriptor)
  }

  public static func fetch(bookID: String) throws -> RecentlyPlayedItem? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<RecentlyPlayedItem> { item in
      item.bookID == bookID
    }
    let descriptor = FetchDescriptor<RecentlyPlayedItem>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existingItem = try RecentlyPlayedItem.fetch(bookID: self.bookID) {
      existingItem.title = self.title
      existingItem.author = self.author
      existingItem.coverURL = self.coverURL
      existingItem.playSessionInfo.merge(with: self.playSessionInfo)
    } else {
      context.insert(self)
    }

    try context.save()
  }

  public func delete() throws {
    cleanupLocalFiles()

    let context = ModelContextProvider.shared.context
    context.delete(self)
    try context.save()
  }

  public func deleteFiles() throws {
    cleanupLocalFiles()

    let context = ModelContextProvider.shared.context
    for track in playSessionInfo.audioTracks ?? [] {
      track.relativePath = nil
    }
    try context.save()
  }

  private func cleanupLocalFiles() {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      .first!
    let bookDirectory = documentsPath.appendingPathComponent("audiobooks").appendingPathComponent(
      bookID)

    do {
      if FileManager.default.fileExists(atPath: bookDirectory.path) {
        try FileManager.default.removeItem(at: bookDirectory)
      }
    } catch {
    }
  }

  public static func deleteAll() throws {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<RecentlyPlayedItem>()
    let allItems = try context.fetch(descriptor)

    for item in allItems {
      item.cleanupLocalFiles()
      context.delete(item)
    }

    try context.save()
  }
}
