import API
import AVFoundation
import Combine
import Foundation
import Logging
import Models
import ReadiumShared

final class NarrationImporter {
  enum ImportError: Error {
    case missingAudio(String)
    case incompleteCopy(String)
    case invalidDuration(String)
    case notEnoughSpace(Int64)
    case missingOverlay
  }

  static let shared = NarrationImporter()

  @Published private(set) var tasks: [String: Task<Void, Never>] = [:]

  private var failedBookIDs: Set<String> = []

  func importIfNeeded(bookID: String) {
    guard tasks[bookID] == nil,
      !failedBookIDs.contains(bookID),
      let book = try? LocalBook.fetch(bookID: bookID),
      book.tracks.isEmpty,
      let ebookURL = book.ebookLocalPath,
      ebookURL.pathExtension.lowercased() == "epub",
      let serverID = Audiobookshelf.shared.authentication.server?.id
    else {
      return
    }

    let task = Task {
      var imported = false
      var failure: Error?

      do {
        imported = try await importNarration(bookID: bookID, from: ebookURL, serverID: serverID)
      } catch {
        failure = error
      }

      guard !Task.isCancelled else { return }
      tasks[bookID] = nil

      guard !imported else { return }
      failedBookIDs.insert(bookID)
      try? FileManager.default.removeItem(at: DownloadManager.narrationDirectory(serverID: serverID, bookID: bookID))

      if let failure {
        AppLogger.download.error("Failed to import narration for \(bookID): \(failure)")
        Toast(error: String(localized: "This book's narration couldn't be prepared.")).show()
      }
    }

    tasks[bookID] = task
  }

  func removeNarration(from book: LocalBook) {
    tasks.removeValue(forKey: book.bookID)?.cancel()
    failedBookIDs.remove(book.bookID)

    if let serverID = Audiobookshelf.shared.authentication.server?.id {
      try? FileManager.default.removeItem(
        at: DownloadManager.narrationDirectory(serverID: serverID, bookID: book.bookID)
      )
    }

    guard book.hasImportedNarration else { return }

    if PlayerManager.shared.current?.id == book.bookID {
      PlayerManager.shared.clearCurrent()
    }

    book.tracks = []
    book.chapters = []
    book.duration = 0
  }

  private func importNarration(bookID: String, from ebookURL: URL, serverID: String) async throws -> Bool {
    let publication = try await EbookPublicationLoader().open(at: ebookURL)
    guard publication.hasGuidedNavigation else { return false }

    guard let overlay = await MediaOverlay.load(from: publication) else { throw ImportError.missingOverlay }

    let audioFiles = overlay.audioFiles

    var audioSize: Int64 = 0
    for audio in audioFiles {
      if case .success(let length?) = await publication.get(audio)?.estimatedLength() {
        audioSize += Int64(length)
      }
    }
    guard DownloadManager.shared.hasEnoughSpace(for: audioSize),
      await StorageManager.shared.canDownload(additionalBytes: audioSize)
    else {
      throw ImportError.notEnoughSpace(audioSize)
    }

    let relativeDirectory = DownloadManager.narrationPath(serverID: serverID, bookID: bookID)
    let directory = DownloadManager.narrationDirectory(serverID: serverID, bookID: bookID)
    try? FileManager.default.removeItem(at: directory)
    try Task.checkCancellation()
    try DownloadManager.shared.prepareDownloadDirectory(directory)

    var tracks: [Track] = []
    var offset: TimeInterval = 0

    for (index, audio) in audioFiles.enumerated() {
      try Task.checkCancellation()

      guard let resource = publication.get(audio) else {
        throw ImportError.missingAudio(audio.string)
      }

      let ext = (audio.path as NSString).pathExtension.lowercased()
      let filename = "\(index + 1).\(ext)"
      let destination = directory.appendingPathComponent(filename)

      let size = try await Self.copy(resource, to: destination)
      let asset = AVURLAsset(url: destination, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
      let duration = try await asset.load(.duration).seconds
      guard duration.isFinite, duration > 0 else {
        throw ImportError.invalidDuration(filename)
      }

      tracks.append(
        Track(
          index: index + 1,
          startOffset: offset,
          duration: duration,
          filename: filename,
          ext: ".\(ext)",
          size: size,
          relativePath: URL(string: "\(relativeDirectory)/\(filename)")
        )
      )
      offset += duration
    }

    guard let timeline = MediaOverlayTimeline(overlay: overlay, trackStartOffsets: tracks.map(\.startOffset)) else {
      throw ImportError.missingOverlay
    }

    let chapters = await chapters(in: publication, timeline: timeline, duration: offset)

    try Task.checkCancellation()

    guard let book = try? LocalBook.fetch(bookID: bookID), book.tracks.isEmpty, book.ebookFile != nil else {
      return false
    }

    book.tracks = tracks
    book.chapters = chapters
    book.duration = offset
    try book.save()

    AppLogger.download.info("Imported narration for \(bookID): \(tracks.count) tracks, \(chapters.count) chapters")
    return true
  }

  private func chapters(
    in publication: Publication,
    timeline: MediaOverlayTimeline,
    duration: TimeInterval
  ) async -> [Chapter] {
    let toc = (try? await publication.tableOfContents().get()) ?? []

    var entries: [(title: String, start: TimeInterval)] = []
    for link in flattened(toc) {
      guard let title = link.title, !title.isEmpty,
        let index = clipIndex(for: link.url(), in: timeline.overlay)
      else {
        continue
      }

      let start = timeline.starts[index]
      guard entries.last.map({ start > $0.start }) ?? true else { continue }
      entries.append((title, start))
    }

    guard !entries.isEmpty else { return [] }
    entries[0].start = 0

    return entries.enumerated().map { index, entry in
      let end = index + 1 < entries.count ? entries[index + 1].start : duration
      return Chapter(id: index, start: entry.start, end: end, title: entry.title)
    }
  }

  private func flattened(_ links: [Link]) -> [Link] {
    links.flatMap { [$0] + flattened($0.children) }
  }

  private func clipIndex(for href: AnyURL, in overlay: MediaOverlay) -> Int? {
    let indices = overlay.clipIndices(in: href)
    return indices.first { overlay.clips[$0].fragment == href.fragment } ?? indices.first
  }

  @concurrent
  private nonisolated static func copy(_ resource: Resource, to destination: URL) async throws -> Int64 {
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw ImportError.incompleteCopy(destination.lastPathComponent)
    }

    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }

    let result = await resource.stream { data in
      try? handle.write(contentsOf: data)
    }

    let written = try handle.offset()

    guard case .success = result,
      case .success(let length?) = await resource.estimatedLength(),
      written == length
    else {
      throw ImportError.incompleteCopy(destination.lastPathComponent)
    }

    return Int64(written)
  }
}
