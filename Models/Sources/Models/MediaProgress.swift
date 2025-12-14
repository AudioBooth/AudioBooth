import API
import CoreData
@preconcurrency import Foundation
import SwiftData

@Model
public final class MediaProgress {
  @Attribute(.unique) public var bookID: String
  public var id: String?
  public var lastPlayedAt: Date
  public var currentTime: TimeInterval
  public var duration: TimeInterval
  public var progress: Double
  public var isFinished: Bool
  public var lastUpdate: Date

  public var remaining: TimeInterval { max(0, duration - currentTime) }

  public init(
    bookID: String,
    id: String? = nil,
    lastPlayedAt: Date = Date(),
    currentTime: TimeInterval = 0,
    duration: TimeInterval = 0,
    progress: Double = 0,
    isFinished: Bool = false,
    lastUpdate: Date = Date()
  ) {
    self.bookID = bookID
    self.id = id
    self.lastPlayedAt = lastPlayedAt
    self.currentTime = currentTime
    self.duration = duration
    self.progress = progress
    self.isFinished = isFinished
    self.lastUpdate = lastUpdate
  }

  public convenience init(from apiProgress: User.MediaProgress) {
    self.init(
      bookID: apiProgress.libraryItemId,
      id: apiProgress.id,
      lastPlayedAt: Date(timeIntervalSince1970: TimeInterval(apiProgress.lastUpdate / 1000)),
      currentTime: apiProgress.currentTime,
      duration: apiProgress.duration,
      progress: max(apiProgress.progress, apiProgress.ebookProgress ?? 0),
      isFinished: apiProgress.isFinished,
      lastUpdate: Date(timeIntervalSince1970: TimeInterval(apiProgress.lastUpdate / 1000))
    )
  }
}

@MainActor
extension MediaProgress {
  private static var cache: [String: Double] = initialize()

  public static func initialize() -> [String: Double] {
    do {
      let allProgress = try fetchAll()
      return Dictionary(uniqueKeysWithValues: allProgress.map { ($0.bookID, $0.progress) })
    } catch {
      return [:]
    }
  }

  public static func progress(for bookID: String) -> Double { cache[bookID, default: 0] }
}

@MainActor
extension MediaProgress {
  public static func fetchAll() throws -> [MediaProgress] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<MediaProgress>(
      sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
    )
    let results = try context.fetch(descriptor)
    return results
  }

  public static func fetch(bookID: String) throws -> MediaProgress? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<MediaProgress> { progress in
      progress.bookID == bookID
    }
    let descriptor = FetchDescriptor<MediaProgress>(predicate: predicate)
    let results = try context.fetch(descriptor)

    return results.first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existingProgress = try MediaProgress.fetch(bookID: self.bookID) {
      existingProgress.id = self.id
      existingProgress.lastPlayedAt = self.lastPlayedAt
      existingProgress.currentTime = self.currentTime
      existingProgress.duration = self.duration
      existingProgress.progress = self.progress
      existingProgress.isFinished = self.isFinished
      existingProgress.lastUpdate = self.lastUpdate
    } else {
      context.insert(self)
    }

    try context.save()
    MediaProgress.cache[self.bookID] = self.progress
  }

  public func delete() throws {
    let context = ModelContextProvider.shared.context
    context.delete(self)
    try context.save()
    MediaProgress.cache.removeValue(forKey: self.bookID)
  }

  public static func deleteAll() throws {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<MediaProgress>()
    let allProgress = try context.fetch(descriptor)

    for progress in allProgress {
      context.delete(progress)
    }

    try context.save()
    cache.removeAll()
  }

  public static func getOrCreate(
    for bookID: String,
    duration: TimeInterval
  ) throws
    -> MediaProgress
  {
    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      return existingProgress
    } else {
      let newProgress = MediaProgress(
        bookID: bookID,
        id: nil,
        duration: duration
      )
      try newProgress.save()
      return newProgress
    }
  }

  public static func updateProgress(
    for bookID: String,
    currentTime: TimeInterval,
    duration: TimeInterval,
    progress: Double
  ) throws {
    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      existingProgress.currentTime = currentTime
      existingProgress.duration = duration
      existingProgress.progress = progress
      existingProgress.lastUpdate = Date()
      existingProgress.isFinished = progress >= 1.0
      try existingProgress.save()
    } else {
      let newProgress = MediaProgress(
        bookID: bookID,
        id: nil,
        lastPlayedAt: Date(),
        currentTime: currentTime,
        duration: duration,
        progress: progress,
        isFinished: progress >= 1.0,
        lastUpdate: Date()
      )
      try newProgress.save()
    }
    cache[bookID] = progress
  }

  public static func markAsFinished(for bookID: String) throws {
    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      existingProgress.progress = 1.0
      existingProgress.isFinished = true
      existingProgress.lastUpdate = Date()
      try existingProgress.save()
    } else {
      let newProgress = MediaProgress(
        bookID: bookID,
        duration: 0,
        progress: 1.0,
        isFinished: true
      )
      try newProgress.save()
    }
    cache[bookID] = 1.0
  }

  @MainActor
  public static func syncFromAPI(userData: User, currentPlayingBookID: String? = nil) throws {
    let context = ModelContextProvider.shared.context

    let allLocalProgress = try MediaProgress.fetchAll()
    let remoteBookIDs = Set(userData.mediaProgress.map(\.libraryItemId))
    let localProgressMap = Dictionary(
      uniqueKeysWithValues: allLocalProgress.map { ($0.bookID, $0) }
    )

    for apiProgress in userData.mediaProgress {
      let remote = MediaProgress(from: apiProgress)

      if let local = localProgressMap[apiProgress.libraryItemId] {
        local.id = remote.id
        local.duration = remote.duration

        if remote.lastUpdate > local.lastUpdate {
          if remote.currentTime != local.currentTime {
            PlaybackHistory.record(
              itemID: local.bookID,
              action: .sync,
              position: remote.currentTime
            )
          }

          local.lastPlayedAt = remote.lastPlayedAt
          local.currentTime = remote.currentTime
          local.progress = remote.progress
          local.isFinished = remote.isFinished
          local.lastUpdate = remote.lastUpdate
        }

        if local.isFinished {
          local.progress = 1.0
        }

        cache[local.bookID] = local.progress
      } else {
        context.insert(remote)
        cache[remote.bookID] = remote.progress
      }
    }

    for localProgress in allLocalProgress {
      if !remoteBookIDs.contains(localProgress.bookID) {
        if let currentPlayingBookID, localProgress.bookID == currentPlayingBookID {
          continue
        }

        context.delete(localProgress)
        cache.removeValue(forKey: localProgress.bookID)
      }
    }

    try context.save()
  }
}
