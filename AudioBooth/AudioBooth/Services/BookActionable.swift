import API
import Foundation
import Models

public protocol BookActionable {
  var bookID: String { get }
}

@MainActor
extension BookActionable {
  public func markAsFinished() async throws {
    try MediaProgress.markAsFinished(for: bookID)

    try await Audiobookshelf.shared.libraries.markAsFinished(bookID: bookID)

    if UserPreferences.shared.removeDownloadOnCompletion {
      if let localBook = try? LocalBook.fetch(bookID: bookID), localBook.isDownloaded {
        removeDownload()
      }
    }
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

    if let book = self as? Book {
      downloadType = book.mediaType == .ebook ? .ebook : .audiobook
    } else if let localBook = self as? LocalBook {
      downloadType = localBook.tracks.isEmpty ? .ebook : .audiobook
    } else {
      downloadType = .audiobook
    }

    DownloadManager.shared.startDownload(for: bookID, type: downloadType)
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
}

extension LocalBook: BookActionable {}
