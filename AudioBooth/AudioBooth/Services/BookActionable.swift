import API
import Foundation
import Models

public protocol BookActionable {
  var bookID: String { get }
  var title: String { get }
  var details: String? { get }
  var coverURL: URL? { get }
}

@MainActor
extension BookActionable {
  public func markAsFinished() async throws {
    try MediaProgress.markAsFinished(for: bookID)

    try await Audiobookshelf.shared.libraries.markAsFinished(bookID: bookID)

    if UserPreferences.shared.removeDownloadOnCompletion {
      if DownloadManager.shared.downloadStates[bookID] == .downloaded {
        removeDownload()
      }
    }

    ReviewRequestManager.shared.recordBookCompletion()
  }

  public func resetProgress() async throws {
    let progress = try MediaProgress.fetch(bookID: bookID)
    let progressID: String

    if let progress, let id = progress.id {
      progressID = id
    } else {
      let apiProgress = try await Audiobookshelf.shared.libraries.fetchMediaProgress(
        bookID: bookID
      )
      progressID = apiProgress.id
    }

    try await Audiobookshelf.shared.libraries.resetBookProgress(progressID: progressID)

    if let progress {
      try progress.delete()
    }
  }

  public func download() throws {
    let downloadType: DownloadManager.DownloadType

    let title: String
    let duration: TimeInterval
    let size: Int64
    let coverURL: URL?

    if let book = self as? Book {
      downloadType = book.mediaType == .ebook ? .ebook : .audiobook

      title = book.title
      duration = book.duration
      size = book.size ?? 0
      coverURL = book.coverURL()
    } else if let localBook = self as? LocalBook {
      downloadType = localBook.tracks.isEmpty ? .ebook : .audiobook

      title = localBook.title
      duration = localBook.duration
      size = localBook.tracks.reduce(0) { $0 + ($1.size ?? 0) }
      coverURL = localBook.coverURL()
    } else {
      throw BookActionableError.unsupportedType
    }

    var details = Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )

    if size > 0 {
      details += " • \(size.formatted(.byteCount(style: .file)))"
    }

    Task {
      let canDownload = await StorageManager.shared.canDownload(additionalBytes: size)
      guard canDownload else {
        Toast(error: "Storage limit reached").show()
        return
      }

      DownloadManager.shared.startDownload(
        for: bookID,
        type: downloadType,
        info: .init(
          title: title,
          details: details,
          coverURL: coverURL,
          startedAt: Date()
        )
      )
    }
  }

  public func removeDownload() {
    DownloadManager.shared.deleteDownload(for: bookID)

    if PlayerManager.shared.current?.id != bookID {
      if let localBook = self as? LocalBook {
        try? localBook.delete()
      } else if let localBook = try? LocalBook.fetch(bookID: bookID) {
        try? localBook.delete()
      }
    }
  }

  public func play() where Self == LocalBook {
    PlayerManager.shared.setCurrent(self)
    PlayerManager.shared.play()
  }

  public func play() where Self == Book {
    PlayerManager.shared.setCurrent(self)
    PlayerManager.shared.play()
  }
}

extension Book: BookActionable {
  public var bookID: String { id }
  public var details: String? {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )
  }
  public var coverURL: URL? { coverURL() }
}

extension LocalBook: BookActionable {
  public var details: String? {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )
  }
  public var coverURL: URL? { coverURL() }
}

enum BookActionableError: Error {
  case unsupportedType
}
