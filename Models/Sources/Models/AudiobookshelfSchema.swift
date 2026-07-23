import API
import Foundation
import SwiftData

enum AudiobookshelfSchema: VersionedSchema {
  static nonisolated(unsafe) var versionIdentifier = Schema.Version(0, 0, 4)

  static var models: [any PersistentModel.Type] {
    [
      LocalBook.self,
      LocalPodcast.self,
      LocalEpisode.self,
      DownloadRequest.self,
      Track.self,
      Chapter.self,
      MediaProgress.self,
      Bookmark.self,
      PlaybackSession.self,
      PlaybackHistory.self,
    ]
  }
}
