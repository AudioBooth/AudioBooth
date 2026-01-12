import API
import AVFoundation
import Foundation
import Logging
import Models
import SwiftUI

final class BookmarkViewerSheetViewModel: BookmarkViewerSheet.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
  }

  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared

  private var item: Item

  init?(item: Item, initialTime: Int? = nil) {
    let bookID: String

    switch item {
    case .local(let book):
      bookID = book.bookID

    case .remote(let book):
      bookID = book.id
    }

    self.item = item

    do {
      let localBookmarks = try Models.Bookmark.fetch(bookID: bookID)

      let bookmarks = localBookmarks.map { bookmark in
        BookmarkRow.Model(
          title: bookmark.title,
          time: bookmark.time,
          createdAt: bookmark.createdAt,
          status: bookmark.status
        )
      }

      if bookmarks.isEmpty, initialTime == nil {
        return nil
      } else {
        super.init(bookmarks: bookmarks, currentTime: initialTime)
      }
    } catch {
      return nil
    }
  }

  override func onAppear() {
    refreshBookmarks()
  }

  private func refreshBookmarks() {
    do {
      let localBookmarks = try Models.Bookmark.fetch(bookID: bookID)

      bookmarks = localBookmarks.map { bookmark in
        BookmarkRow.Model(
          title: bookmark.title,
          time: bookmark.time,
          createdAt: bookmark.createdAt,
          status: bookmark.status
        )
      }
    } catch {
      AppLogger.player.error("Failed to refresh bookmarks: \(error)")
    }
  }

  override func onSelectBookmark(_ bookmark: BookmarkRow.Model) {

    if let currentPlayer = playerManager.current,
      currentPlayer.id == bookID,
      let bookPlayerModel = currentPlayer as? BookPlayerModel
    {
      bookPlayerModel.seekToTime(Double(bookmark.time))
    } else {
      switch item {
      case .local(let book):
        openLocalBookmark(bookmark, for: book)

      case .remote(let book):
        openRemoteBookmark(bookmark, for: book)
      }
    }

    isPresented = false
  }

  private func openRemoteBookmark(_ bookmark: BookmarkRow.Model, for book: Book) {
    Task {
      if let currentPlayer = playerManager.current,
        currentPlayer.id == book.id,
        let bookPlayerModel = currentPlayer as? BookPlayerModel
      {
        bookPlayerModel.seekToTime(Double(bookmark.time))
        playerManager.showFullPlayer()
      } else {
        playerManager.setCurrent(book)
        if let bookPlayerModel = playerManager.current as? BookPlayerModel {
          bookPlayerModel.seekToTime(Double(bookmark.time))
        }
        playerManager.showFullPlayer()
      }

      AppLogger.player.info("Jumped to bookmark at \(bookmark.time)s")
    }
  }

  private func openLocalBookmark(_ bookmark: BookmarkRow.Model, for book: LocalBook) {
    Task {
      if let currentPlayer = playerManager.current,
        currentPlayer.id == book.bookID,
        let bookPlayerModel = currentPlayer as? BookPlayerModel
      {
        bookPlayerModel.seekToTime(Double(bookmark.time))
        playerManager.showFullPlayer()
      } else {
        playerManager.setCurrent(book)
        if let bookPlayerModel = playerManager.current as? BookPlayerModel {
          bookPlayerModel.seekToTime(Double(bookmark.time))
        }
        playerManager.showFullPlayer()
      }

      AppLogger.player.info("Jumped to bookmark at \(bookmark.time)s")
    }
  }

  override func onEditBookmark(_ bookmark: BookmarkRow.Model) {
    Task {
      do {
        guard let localBookmark = try Bookmark.fetch(bookID: bookID, time: bookmark.time) else {
          throw Bookmark.Error.notFound
        }

        try await BookmarkSyncQueue.shared.update(
          bookmark: localBookmark,
          newTitle: bookmark.title
        )

        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
          bookmarks[index].title = bookmark.title
        }

        AppLogger.player.info("Updated bookmark: \(bookmark.title)")
        Toast(message: "Bookmark updated").show()
      } catch {
        AppLogger.player.error("Failed to update bookmark: \(error)")
        Toast(error: "Failed to update bookmark").show()
      }
    }
  }

  override func onDeleteBookmark(_ bookmark: BookmarkRow.Model) {
    Task {
      do {
        guard let localBookmark = try Models.Bookmark.fetch(bookID: bookID, time: bookmark.time)
        else {
          throw Bookmark.Error.notFound
        }

        try await BookmarkSyncQueue.shared.delete(localBookmark)

        bookmarks.removeAll { $0.id == bookmark.id }

        AppLogger.player.info("Deleted bookmark at \(bookmark.time)s")
        Toast(message: "Bookmark deleted").show()
      } catch {
        AppLogger.player.error("Failed to delete bookmark: \(error)")
        Toast(error: "Failed to delete bookmark").show()
      }
    }
  }

  override func onCreateBookmark() {
    guard let time = currentTime else { return }

    let trimmedTitle = newBookmarkTitle.trimmingCharacters(in: .whitespaces)
    let title: String

    if trimmedTitle.isEmpty {
      let formatter = DateFormatter()
      formatter.dateFormat = "M/d/yyyy HH:mm"
      title = formatter.string(from: Date())
    } else {
      title = trimmedTitle
    }

    Task {
      do {
        let bookmark = try await BookmarkSyncQueue.shared.create(
          bookID: bookID,
          title: title,
          time: time
        )

        let bookmarkRowModel = BookmarkRow.Model(
          title: bookmark.title,
          time: bookmark.time,
          createdAt: bookmark.createdAt,
          status: bookmark.status
        )

        bookmarks.append(bookmarkRowModel)
        bookmarks.sort { $0.createdAt > $1.createdAt }

        newBookmarkTitle = ""

        AppLogger.player.info("Created bookmark: \(title) at \(time)s")
        Toast(message: "Bookmark created").show()

        isPresented = false
      } catch {
        AppLogger.player.error("Failed to save bookmark locally: \(error)")
        Toast(error: "Failed to save bookmark").show()
      }
    }
  }
}

extension BookmarkViewerSheetViewModel {
  var bookID: String {
    switch item {
    case .local(let book): book.bookID
    case .remote(let book): book.id
    }
  }
}
