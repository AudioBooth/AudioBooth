import Foundation
import SwiftData

@Model
public final class PlaybackSession {
  @Attribute(.unique) public var id: String
  public var libraryItemID: String

  public var startTime: TimeInterval
  public var currentTime: TimeInterval
  public var timeListening: TimeInterval
  public var pendingListeningTime: TimeInterval
  public var duration: TimeInterval
  public var startedAt: Date
  public var updatedAt: Date

  public var baseURL: URL?
  public var displayTitle: String?
  public var displayAuthor: String?

  public init(
    id: String = UUID().uuidString,
    libraryItemID: String,
    startTime: TimeInterval,
    currentTime: TimeInterval,
    timeListening: TimeInterval = 0,
    pendingListeningTime: TimeInterval = 0,
    duration: TimeInterval,
    startedAt: Date = Date(),
    updatedAt: Date = Date(),
    baseURL: URL? = nil,
    displayTitle: String? = nil,
    displayAuthor: String? = nil
  ) {
    self.id = id
    self.libraryItemID = libraryItemID
    self.startTime = startTime
    self.currentTime = currentTime
    self.timeListening = timeListening
    self.pendingListeningTime = pendingListeningTime
    self.duration = duration
    self.startedAt = startedAt
    self.updatedAt = updatedAt
    self.baseURL = baseURL
    self.displayTitle = displayTitle
    self.displayAuthor = displayAuthor
  }

  public var progress: Double {
    guard duration > 0 else { return 0 }
    return currentTime / duration
  }

  public var isRemote: Bool {
    baseURL != nil
  }

  public func url(for track: Track) -> URL? {
    if let localPath = track.localPath {
      return localPath
    }
    guard let baseURL else { return nil }
    return baseURL.appendingPathComponent("track/\(track.index)")
  }
}

@MainActor
extension PlaybackSession {
  public static func fetchAll() throws -> [PlaybackSession] {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<PlaybackSession> { session in
      session.timeListening > 0 || session.pendingListeningTime > 0
    }
    let descriptor = FetchDescriptor<PlaybackSession>(
      predicate: predicate,
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    return try context.fetch(descriptor)
  }

  public static func fetchUnsynced() throws -> [PlaybackSession] {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<PlaybackSession> { session in
      session.pendingListeningTime > 0
    }
    let descriptor = FetchDescriptor<PlaybackSession>(predicate: predicate)
    return try context.fetch(descriptor)
  }

  public static func fetch(id: String) throws -> PlaybackSession? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<PlaybackSession> { session in
      session.id == id
    }
    let descriptor = FetchDescriptor<PlaybackSession>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context
    if let existing = try PlaybackSession.fetch(id: self.id) {
      existing.currentTime = self.currentTime
      existing.timeListening = self.timeListening
      existing.pendingListeningTime = self.pendingListeningTime
      existing.updatedAt = self.updatedAt
      existing.displayTitle = self.displayTitle
      existing.displayAuthor = self.displayAuthor
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

  public static func cleanupOldSessions() throws {
    let context = ModelContextProvider.shared.context
    let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    let predicate = #Predicate<PlaybackSession> { session in
      session.pendingListeningTime == 0 && session.updatedAt < sevenDaysAgo
    }
    let descriptor = FetchDescriptor<PlaybackSession>(predicate: predicate)
    let oldSessions = try context.fetch(descriptor)
    for session in oldSessions {
      context.delete(session)
    }
    try context.save()
  }
}
