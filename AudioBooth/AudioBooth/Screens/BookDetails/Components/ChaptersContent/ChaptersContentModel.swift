import API
import Foundation
import Models

final class ChaptersContentModel: ChaptersContent.Model {
  private let book: Book?
  private let localBook: LocalBook?
  private let bookID: String
  private var playerManager: PlayerManager { .shared }

  init(
    chapters: [ChaptersContent.Chapter],
    book: Book?,
    localBook: LocalBook?,
    bookID: String
  ) {
    self.book = book
    self.localBook = localBook
    self.bookID = bookID
    super.init(chapters: chapters)
  }

  override func onChapterTapped(_ chapter: ChaptersContent.Chapter) {
    if let book {
      playChapter(chapter, for: book)
    } else if let localBook {
      playChapter(chapter, for: localBook)
    } else {
      Toast(error: "Book not available").show()
    }
  }

  private func playChapter(_ chapter: ChaptersContent.Chapter, for book: Book) {
    if playerManager.current?.id == bookID {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        if chapter.status == .current && !currentPlayer.isPlaying {
          currentPlayer.onTogglePlaybackTapped()
        } else {
          currentPlayer.seekToTime(chapter.start)
          if !currentPlayer.isPlaying {
            currentPlayer.onTogglePlaybackTapped()
          }
        }
      }
    } else {
      playerManager.setCurrent(book)
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.seekToTime(chapter.start)
        PlayerManager.shared.play()
      }
    }
  }

  private func playChapter(_ chapter: ChaptersContent.Chapter, for localBook: LocalBook) {
    if playerManager.current?.id == bookID {
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        if chapter.status == .current && !currentPlayer.isPlaying {
          currentPlayer.onTogglePlaybackTapped()
        } else {
          currentPlayer.seekToTime(chapter.start)
          if !currentPlayer.isPlaying {
            currentPlayer.onTogglePlaybackTapped()
          }
        }
      }
    } else {
      playerManager.setCurrent(localBook)
      if let currentPlayer = playerManager.current as? BookPlayerModel {
        currentPlayer.seekToTime(chapter.start)
        PlayerManager.shared.play()
      }
    }
  }
}
