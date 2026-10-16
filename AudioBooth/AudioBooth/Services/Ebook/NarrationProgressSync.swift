import API
import Foundation
import Logging
import Models
import ReadiumShared

final class NarrationProgressSync {
  private static let secondsBetweenServerSyncs: TimeInterval = 30

  static var openReaderBookID: String?

  private let bookID: String
  private let mediaProgress: MediaProgress
  private var timeline: MediaOverlayTimeline?
  private var lastServerSyncAt: Date?

  init?(book: LocalBook, mediaProgress: MediaProgress) {
    guard book.hasImportedNarration, let ebookURL = book.ebookLocalPath else { return nil }

    bookID = book.bookID
    self.mediaProgress = mediaProgress
    let trackStartOffsets = book.orderedTracks.map(\.startOffset)

    Task { [weak self] in
      guard let publication = try? await EbookPublicationLoader().open(at: ebookURL) else { return }

      self?.timeline = await MediaOverlayTimeline.load(from: publication, trackStartOffsets: trackStartOffsets)
    }
  }

  func update() {
    guard Self.openReaderBookID != bookID,
      let timeline,
      mediaProgress.duration > 0,
      let index = timeline.clipIndex(at: mediaProgress.currentTime),
      let ebookLocation = try? timeline.overlay.clips[index].text.jsonString()
    else {
      return
    }

    let ebookProgress = min(1, max(0, mediaProgress.currentTime / mediaProgress.duration))
    mediaProgress.ebookProgress = ebookProgress
    mediaProgress.ebookLocation = ebookLocation

    let now = Date()
    if let lastServerSyncAt, now.timeIntervalSince(lastServerSyncAt) < Self.secondsBetweenServerSyncs {
      return
    }
    lastServerSyncAt = now

    let currentTime = mediaProgress.currentTime

    Task { [bookID] in
      do {
        try await Audiobookshelf.shared.progress.update(
          bookID: bookID,
          currentTime: currentTime,
          ebookProgress: ebookProgress,
          ebookLocation: ebookLocation
        )
      } catch {
        AppLogger.player.error("Failed to sync narration ebook progress: \(error)")
      }
    }
  }
}
