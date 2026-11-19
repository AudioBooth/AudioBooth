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

    try await Audiobookshelf.shared.progress.markAsFinished(bookID: bookID)

    if UserPreferences.shared.removeDownloadOnCompletion {
      if DownloadManager.shared.downloadStates[bookID] == .downloaded, PlayerManager.shared.current?.id != bookID {
        removeDownload()
      }
    }

    ReviewRequestManager.shared.recordBookCompletion()
  }

  public func resetProgress() async throws {
    let progress = try MediaProgress.fetch(bookID: bookID)

    if let progressID = progress?.id {
      try await Audiobookshelf.shared.progress.reset(progressID: progressID)
    } else if let apiProgress = try await Audiobookshelf.shared.progress.fetch(bookID: bookID) {
      try await Audiobookshelf.shared.progress.reset(progressID: apiProgress.id)
    }

    try progress?.delete()
  }

  public func download() throws {
    if let book = self as? Book {
      DownloadManager.shared.startDownload(book)
    } else if let localBook = self as? LocalBook {
      DownloadManager.shared.startDownload(localBook)
    } else {
      throw BookActionableError.unsupportedType
    }
  }

  public func removeDownload() {
    DownloadManager.shared.deleteDownload(for: bookID)
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
