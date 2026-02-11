import API
@preconcurrency import Foundation
import SwiftData

@Model
public final class LocalEpisode {
  @Attribute(.unique) public var episodeID: String
  public var podcast: LocalPodcast?
  public var title: String
  public var duration: TimeInterval
  public var season: String?
  public var episode: String?
  public var episodeDescription: String?
  public var publishedAt: Date?
  public var coverURL: URL?
  public var track: Track?
  public var chapters: [Chapter]

  public var isDownloaded: Bool { track?.relativePath != nil }

  public var orderedTracks: [Track] {
    if let track { return [track] } else { return [] }
  }

  public var orderedChapters: [Chapter] {
    chapters.sorted(by: { $0.start < $1.start })
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

  public func track(at time: TimeInterval) -> Track? {
    track
  }

  public init(
    episodeID: String,
    podcast: LocalPodcast,
    title: String,
    duration: TimeInterval,
    season: String? = nil,
    episode: String? = nil,
    episodeDescription: String? = nil,
    publishedAt: Date? = nil,
    coverURL: URL? = nil,
    track: Track? = nil,
    chapters: [Chapter] = []
  ) {
    self.episodeID = episodeID
    self.podcast = podcast
    self.title = title
    self.duration = duration
    self.season = season
    self.episode = episode
    self.episodeDescription = episodeDescription
    self.publishedAt = publishedAt
    self.coverURL = coverURL
    self.track = track
    self.chapters = chapters
  }
}

extension LocalEpisode: PlayableItem {
  public var itemID: String { episodeID }
  public var details: String { podcast?.author ?? "" }
}

@MainActor
extension LocalEpisode {
  public static func fetchAll() throws -> [LocalEpisode] {
    let context = ModelContextProvider.shared.context
    let descriptor = FetchDescriptor<LocalEpisode>()
    return try context.fetch(descriptor)
  }

  public static func fetch(episodeID: String) throws -> LocalEpisode? {
    let context = ModelContextProvider.shared.context
    let predicate = #Predicate<LocalEpisode> { item in
      item.episodeID == episodeID
    }
    let descriptor = FetchDescriptor<LocalEpisode>(predicate: predicate)
    return try context.fetch(descriptor).first
  }

  public func save() throws {
    let context = ModelContextProvider.shared.context

    if let existing = try LocalEpisode.fetch(episodeID: self.episodeID) {
      existing.podcast = self.podcast
      existing.title = self.title
      existing.duration = self.duration
      existing.season = self.season
      existing.episode = self.episode
      existing.episodeDescription = self.episodeDescription
      existing.publishedAt = self.publishedAt
      existing.coverURL = self.coverURL
      existing.chapters = self.chapters

      if let newTrack = self.track {
        let existingRelativePath = existing.track?.relativePath
        existing.track = newTrack
        if existingRelativePath != nil && newTrack.relativePath == nil {
          existing.track?.relativePath = existingRelativePath
        }
      }
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
}
