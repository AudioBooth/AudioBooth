import Foundation
import SwiftData

@Model
final class RecentlyPlayedItem {
  @Attribute(.unique) var bookID: String
  var title: String
  var author: String?
  var coverURL: URL?
  var lastPlayedAt: Date
  var currentTime: TimeInterval
  var timeListened: TimeInterval
  var duration: TimeInterval?
  var playSessionInfo: PlaySessionInfo

  init(
    bookID: String,
    title: String,
    author: String? = nil,
    coverURL: URL? = nil,
    lastPlayedAt: Date = Date(),
    currentTime: TimeInterval = 0,
    timeListened: TimeInterval = 0,
    duration: TimeInterval? = nil,
    playSessionInfo: PlaySessionInfo
  ) {
    self.bookID = bookID
    self.title = title
    self.author = author
    self.coverURL = coverURL
    self.lastPlayedAt = lastPlayedAt
    self.currentTime = currentTime
    self.timeListened = timeListened
    self.duration = duration
    self.playSessionInfo = playSessionInfo
  }
}

extension RecentlyPlayedItem {
  var progress: Double {
    guard let duration = duration, duration > 0 else { return 0 }
    return min(currentTime / duration, 1.0)
  }
}

extension RecentlyPlayedItem {
  @MainActor
  static func fetchAll() throws -> [RecentlyPlayedItem] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<RecentlyPlayedItem>(
      sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
    )
    return try context.fetch(descriptor)
  }

  @MainActor
  static func observeAll() -> AsyncStream<[RecentlyPlayedItem]> {
    AsyncStream { continuation in
      let context = ModelContextProvider.shared.context
      let descriptor = FetchDescriptor<RecentlyPlayedItem>(
        sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
      )

      let fetchData = {
        do {
          let items = try context.fetch(descriptor)
          continuation.yield(items)
        } catch {
          print("Failed to fetch RecentlyPlayedItem: \(error)")
          continuation.yield([])
        }
      }

      fetchData()

      let observer = NotificationCenter.default.addObserver(
        forName: ModelContext.didSave,
        object: context,
        queue: .main
      ) { _ in
        fetchData()
      }

      continuation.onTermination = { _ in
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  @MainActor
  static func fetch(bookID: String) throws -> RecentlyPlayedItem? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<RecentlyPlayedItem> { item in
      item.bookID == bookID
    }
    let descriptor = FetchDescriptor<RecentlyPlayedItem>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  @MainActor
  func save() throws {
    let context = ModelContextProvider.shared.context

    if let existingItem = try RecentlyPlayedItem.fetch(bookID: self.bookID) {
      existingItem.title = self.title
      existingItem.author = self.author
      existingItem.coverURL = self.coverURL
      existingItem.lastPlayedAt = self.lastPlayedAt
      existingItem.currentTime = self.currentTime
      existingItem.timeListened = self.timeListened
      existingItem.duration = self.duration
      existingItem.playSessionInfo.merge(with: self.playSessionInfo)
    } else {
      context.insert(self)
    }

    try context.save()
  }

  @MainActor
  func delete() throws {
    cleanupLocalFiles()

    let context = ModelContextProvider.shared.context
    context.delete(self)
    try context.save()
  }

  @MainActor
  func deleteFiles() throws {
    cleanupLocalFiles()

    let context = ModelContextProvider.shared.context
    for track in playSessionInfo.audioTracks ?? [] {
      track.fileName = nil
    }
    try context.save()
  }

  private func cleanupLocalFiles() {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      .first!
    let bookDirectory = documentsPath.appendingPathComponent("Downloads").appendingPathComponent(
      bookID)

    do {
      if FileManager.default.fileExists(atPath: bookDirectory.path) {
        try FileManager.default.removeItem(at: bookDirectory)
        print("Cleaned up local files for book: \(title)")
      }
    } catch {
      print("Failed to clean up local files for book \(title): \(error)")
    }
  }

  @MainActor
  static func deleteAll() throws {
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
