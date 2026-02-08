import API
@preconcurrency import Foundation
import SwiftData

@Model
public final class LocalPodcast {
  @Attribute(.unique) public var podcastID: String
  public var title: String
  public var author: String?
  public var coverURL: URL?
  public var podcastDescription: String?
  public var genres: [String]?
  public var feedURL: String?
  public var language: String?
  public var podcastType: String?

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
    podcastID: String,
    title: String,
    author: String? = nil,
    coverURL: URL? = nil,
    podcastDescription: String? = nil,
    genres: [String]? = nil,
    feedURL: String? = nil,
    language: String? = nil,
    podcastType: String? = nil
  ) {
    self.podcastID = podcastID
    self.title = title
    self.author = author
    self.coverURL = coverURL
    self.podcastDescription = podcastDescription
    self.genres = genres
    self.feedURL = feedURL
    self.language = language
    self.podcastType = podcastType
  }

  public convenience init(from podcast: Podcast) {
    self.init(
      podcastID: podcast.id,
      title: podcast.title,
      author: podcast.author,
      coverURL: podcast.coverURL(),
      podcastDescription: podcast.description,
      genres: podcast.genres,
      feedURL: podcast.feedURL,
      language: podcast.language,
      podcastType: podcast.podcastType
    )
  }
}

@MainActor
extension LocalPodcast {
  public static func fetchAll() throws -> [LocalPodcast] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<LocalPodcast>()
    return try context.fetch(descriptor)
  }

  public static func fetch(podcastID: String) throws -> LocalPodcast? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<LocalPodcast> { item in
      item.podcastID == podcastID
    }
    let descriptor = FetchDescriptor<LocalPodcast>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existing = try LocalPodcast.fetch(podcastID: self.podcastID) {
      existing.title = self.title
      existing.author = self.author
      existing.coverURL = self.coverURL
      existing.podcastDescription = self.podcastDescription
      existing.genres = self.genres
      existing.feedURL = self.feedURL
      existing.language = self.language
      existing.podcastType = self.podcastType
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
    let descriptor = FetchDescriptor<LocalPodcast>()
    let allItems = try context.fetch(descriptor)
    for item in allItems {
      context.delete(item)
    }
    try context.save()
  }
}
