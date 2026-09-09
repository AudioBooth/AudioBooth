import Foundation
import Models

nonisolated struct PageMatchBookContext: Sendable {
  let bookID: String
  let title: String
  let chapters: [AudioChapter]
  let duration: TimeInterval
  let source: NarrationSource?
  let locale: Locale
  let languageCode: String?
  let ebookURL: URL?

  var isDownloaded: Bool { source != nil }

  @MainActor
  init(localBook: LocalBook) {
    bookID = localBook.bookID
    title = localBook.title
    chapters = localBook.orderedChapters.map {
      AudioChapter(title: $0.title, start: $0.start, end: $0.end)
    }
    duration = localBook.duration
    source = NarrationSource(downloaded: localBook.orderedTracks)
    languageCode = BookLanguage.code(for: localBook.language)
    locale = languageCode.map { Locale(identifier: $0) } ?? Locale.current
    ebookURL = localBook.ebookLocalPath
  }
}
