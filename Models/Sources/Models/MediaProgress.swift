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
  public var ebookProgress: Double?
  public var ebookLocation: String?
  public var isFinished: Bool
  public var startedAt: Date = Date()
  public var finishedAt: Date?
  public var lastUpdate: Date

  public var remaining: TimeInterval { max(0, duration - currentTime) }

  public init(
    bookID: String,
    id: String? = nil,
    lastPlayedAt: Date = Date(),
    currentTime: TimeInterval = 0,
    duration: TimeInterval = .infinity,
    progress: Double = 0,
    ebookProgress: Double? = nil,
    ebookLocation: String? = nil,
    isFinished: Bool = false,
    startedAt: Date = Date(),
    finishedAt: Date? = nil,
    lastUpdate: Date = Date()
  ) {
    self.bookID = bookID
    self.id = id
    self.lastPlayedAt = lastPlayedAt
    self.currentTime = currentTime
    self.duration = duration
    self.progress = progress
    self.ebookProgress = ebookProgress
    self.ebookLocation = ebookLocation
    self.isFinished = isFinished
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.lastUpdate = lastUpdate
  }

  public convenience init(from apiProgress: User.MediaProgress) {
    var progress = apiProgress.progress
    var currentTime = apiProgress.currentTime

    if apiProgress.isFinished {
      progress = 1.0
      currentTime = apiProgress.duration ?? 0
    }

    let lastUpdate = Date(timeIntervalSince1970: TimeInterval(apiProgress.lastUpdate / 1000))
    let startedAt = Date(timeIntervalSince1970: TimeInterval(apiProgress.startedAt / 1000))

    self.init(
      bookID: apiProgress.episodeId ?? apiProgress.libraryItemId,
      id: apiProgress.id,
      lastPlayedAt: lastUpdate,
      currentTime: currentTime,
      duration: apiProgress.duration ?? 0,
      progress: progress,
      ebookProgress: apiProgress.ebookProgress,
      ebookLocation: apiProgress.ebookLocation,
      isFinished: apiProgress.isFinished,
      startedAt: startedAt,
      finishedAt: apiProgress.finishedAt.map { Date(timeIntervalSince1970: TimeInterval($0 / 1000)) },
      lastUpdate: lastUpdate
    )
  }
}

@MainActor
extension MediaProgress {
  private static var cache: [String: Double] = initialize()

  public static func initialize() -> [String: Double] {
    do {
      let allProgress = try fetchAll()
      return Dictionary(
        uniqueKeysWithValues: allProgress.map {
          if $0.progress > 0 {
            return ($0.bookID, $0.progress)
          } else {
            return ($0.bookID, $0.ebookProgress ?? 0)
          }
        }
      )
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

    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      existingProgress.id = id
      existingProgress.lastPlayedAt = lastPlayedAt
      existingProgress.currentTime = currentTime
      existingProgress.duration = duration
      existingProgress.progress = progress
      existingProgress.ebookLocation = ebookLocation
      existingProgress.isFinished = isFinished
      existingProgress.finishedAt = finishedAt
      existingProgress.lastUpdate = lastUpdate
    } else {
      context.insert(self)
    }

    try context.save()

    if progress > 0 {
      MediaProgress.cache[bookID] = progress
    } else if let progress = ebookProgress {
      MediaProgress.cache[bookID] = progress
    }
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
      existingProgress.duration = duration
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

  public static func updateEbookProgress(
    for bookID: String,
    ebookProgress: Double,
    ebookLocation: String? = nil
  ) throws {
    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      existingProgress.ebookProgress = ebookProgress
      existingProgress.ebookLocation = ebookLocation
      existingProgress.lastUpdate = Date()
      try existingProgress.save()

      if existingProgress.progress == 0 {
        cache[bookID] = ebookProgress
      }
    } else {
      let newProgress = MediaProgress(
        bookID: bookID,
        id: nil,
        lastPlayedAt: Date(),
        ebookProgress: ebookProgress,
        ebookLocation: ebookLocation,
        lastUpdate: Date()
      )
      try newProgress.save()
      cache[bookID] = ebookProgress
    }
  }

  public static func markAsFinished(for bookID: String) throws {
    if let existingProgress = try MediaProgress.fetch(bookID: bookID) {
      existingProgress.progress = 1.0
      existingProgress.currentTime = existingProgress.duration
      existingProgress.isFinished = true
      existingProgress.finishedAt = Date()
      existingProgress.lastUpdate = Date()
      try existingProgress.save()
    } else {
      let newProgress = MediaProgress(
        bookID: bookID,
        duration: 0,
        progress: 1.0,
        isFinished: true,
        finishedAt: Date()
      )
      try newProgress.save()
    }
    cache[bookID] = 1.0
  }

  @MainActor
  public static func syncFromAPI(userData: User, currentPlayingBookID: String? = nil) throws {
    let context = ModelContextProvider.shared.context

    let allLocalProgress = try MediaProgress.fetchAll()
    let remoteBookIDs = Set(userData.mediaProgress.map { $0.episodeId ?? $0.libraryItemId })
    let localProgressMap = Dictionary(
      uniqueKeysWithValues: allLocalProgress.map { ($0.bookID, $0) }
    )

    for apiProgress in userData.mediaProgress {
      let remote = MediaProgress(from: apiProgress)

      if let local = localProgressMap[apiProgress.episodeId ?? apiProgress.libraryItemId] {
        local.id = remote.id
        local.duration = remote.duration
        local.startedAt = remote.startedAt

        if local.finishedAt == nil {
          local.finishedAt = remote.finishedAt
        }

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
          local.ebookLocation = remote.ebookLocation
          local.isFinished = remote.isFinished
          local.finishedAt = remote.finishedAt
          local.lastUpdate = remote.lastUpdate
        }

        if local.progress > 0 {
          cache[local.bookID] = local.progress
        } else if let progress = local.ebookProgress {
          cache[local.bookID] = progress
        }
      } else {
        context.insert(remote)

        if remote.progress > 0 {
          cache[remote.bookID] = remote.progress
        } else if let progress = remote.ebookProgress {
          cache[remote.bookID] = progress
        }
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
