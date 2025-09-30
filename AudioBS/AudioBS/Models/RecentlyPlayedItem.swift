import Foundation
import SwiftData

@Model
final class RecentlyPlayedItem {
  @Attribute(.unique) var bookID: String
  var title: String
  var author: String?
  var coverURL: URL?
  var playSessionInfo: PlaySessionInfo

  init(
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

extension RecentlyPlayedItem {

  static func fetchAll() throws -> [RecentlyPlayedItem] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<RecentlyPlayedItem>()
    return try context.fetch(descriptor)
  }

  static func observeAll() -> AsyncStream<[RecentlyPlayedItem]> {
    AsyncStream { continuation in
      let context = ModelContextProvider.shared.context
      let appStateManager = AppStateManager.shared
      let descriptor = FetchDescriptor<RecentlyPlayedItem>()
      var isProcessingNotification = false

      let fetchData = {
        guard !appStateManager.isInBackground else { return }
        do {
          let items = try context.fetch(descriptor)
          continuation.yield(items)
        } catch {
          continuation.yield([])
        }
      }

      fetchData()

      let observer = NotificationCenter.default.addObserver(
        forName: ModelContext.didSave,
        object: context,
        queue: .main
      ) { _ in
        guard !isProcessingNotification else { return }
        isProcessingNotification = true
        fetchData()
        isProcessingNotification = false
      }

      continuation.onTermination = { _ in
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  static func fetch(bookID: String) throws -> RecentlyPlayedItem? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<RecentlyPlayedItem> { item in
      item.bookID == bookID
    }
    let descriptor = FetchDescriptor<RecentlyPlayedItem>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  func save() throws {
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

  func delete() throws {
    cleanupLocalFiles()

    let context = ModelContextProvider.shared.context
    context.delete(self)
    try context.save()
  }

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
    let bookDirectory = documentsPath.appendingPathComponent("audiobooks").appendingPathComponent(
      bookID)

    do {
      if FileManager.default.fileExists(atPath: bookDirectory.path) {
        try FileManager.default.removeItem(at: bookDirectory)
      }
    } catch {
    }
  }

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
