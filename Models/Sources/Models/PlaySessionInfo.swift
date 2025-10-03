import Audiobookshelf
import Foundation
import SwiftData

@Model
public final class PlaySessionInfo {
  public var id: String
  public var createdAt: Date
  public var userId: String
  public var libraryItemID: String
  public var duration: TimeInterval
  public var audioTracks: [AudioTrackInfo]?
  public var chapters: [ChapterInfo]?

  public init(from session: PlaySession) {
    self.id = session.id
    self.createdAt = Date()
    self.userId = session.userId
    self.libraryItemID = session.libraryItemId
    self.duration = session.duration
    self.audioTracks = session.streamingTracks?.map(AudioTrackInfo.init)
    self.chapters = session.chapters?.map(ChapterInfo.init)
  }
}

extension PlaySessionInfo {
  private func fileURL(for track: AudioTrackInfo) -> URL? {
    return track.localPath
  }

  public func track(at time: TimeInterval) -> AudioTrackInfo? {
    guard let tracks = orderedTracks else { return nil }

    var currentTime: TimeInterval = 0
    for track in tracks {
      if time >= currentTime && time < currentTime + track.duration {
        return track
      }
      currentTime += track.duration
    }

    return nil
  }

  public var isExpired: Bool {
    if isDownloaded { return false }
    return Date().timeIntervalSince(createdAt) > 24 * 60 * 60
  }

  public var isDownloaded: Bool {
    guard let tracks = orderedTracks, !tracks.isEmpty else { return false }

    return tracks.allSatisfy { track in
      return fileURL(for: track) != nil
    }
  }

  public var orderedChapters: [ChapterInfo]? {
    chapters?.sorted(by: { $0.start < $1.start })
  }

  public var orderedTracks: [AudioTrackInfo]? {
    audioTracks?.sorted(by: { $0.index < $1.index })
  }

  public func merge(with newSessionInfo: PlaySessionInfo) {
    self.id = newSessionInfo.id
    self.createdAt = newSessionInfo.createdAt
    self.userId = newSessionInfo.userId
    self.libraryItemID = newSessionInfo.libraryItemID
    self.duration = newSessionInfo.duration
    self.chapters = newSessionInfo.chapters

    guard let newTracks = newSessionInfo.audioTracks else {
      audioTracks = nil
      return
    }

    var mergedTracks: [AudioTrackInfo] = []

    for newTrack in newTracks {
      if let existingTrack = audioTracks?.first(where: { $0.index == newTrack.index }) {
        newTrack.relativePath = existingTrack.relativePath
      }
      mergedTracks.append(newTrack)
    }

    self.audioTracks = mergedTracks
  }
}
