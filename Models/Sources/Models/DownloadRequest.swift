import Foundation
import SwiftData

@Model
public final class DownloadRequest {
  @Attribute(.unique) public var itemID: String
  public var kind: Kind
  public var podcastID: String?
  public var title: String
  public var coverURL: URL?
  public var duration: TimeInterval
  public var size: Int64
  public var createdAt: Date
  public var failureCount: Int = 0

  public enum Kind: String, Codable {
    case book
    case ebook
    case episode
  }

  public static let maxFailures = 3

  public var hasFailed: Bool {
    failureCount >= Self.maxFailures
  }

  public init(
    itemID: String,
    kind: Kind,
    podcastID: String? = nil,
    title: String,
    coverURL: URL? = nil,
    duration: TimeInterval = 0,
    size: Int64 = 0,
    createdAt: Date = Date()
  ) {
    self.itemID = itemID
    self.kind = kind
    self.podcastID = podcastID
    self.title = title
    self.coverURL = coverURL
    self.duration = duration
    self.size = size
    self.createdAt = createdAt
  }
}

@MainActor
extension DownloadRequest {
  public static func fetchAll() throws -> [DownloadRequest] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<DownloadRequest>()
    return try context.fetch(descriptor)
  }

  public static func fetch(itemID: String) throws -> DownloadRequest? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<DownloadRequest> { request in
      request.itemID == itemID
    }
    let descriptor = FetchDescriptor<DownloadRequest>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existing = try DownloadRequest.fetch(itemID: self.itemID) {
      existing.kind = self.kind
      existing.podcastID = self.podcastID
      existing.title = self.title
      existing.coverURL = self.coverURL
      existing.duration = self.duration
      if self.size > 0 {
        existing.size = self.size
      }
    } else {
      context.insert(self)
    }

    try? context.save()
  }

  public func delete() throws {
    let context = ModelContextProvider.shared.context
    context.delete(self)
    try? context.save()
  }
}

extension DownloadRequest: Comparable {
  public static func < (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
    if (lhs.kind == .ebook) != (rhs.kind == .ebook) {
      return lhs.kind == .ebook
    } else {
      return lhs.createdAt < rhs.createdAt
    }
  }
}
