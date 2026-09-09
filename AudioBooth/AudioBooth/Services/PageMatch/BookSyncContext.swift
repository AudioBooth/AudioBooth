import Foundation
import Models

nonisolated struct BookSyncContext: Sendable {
  let bookID: String
  let title: String
  let chapters: [AudioChapter]
  let duration: TimeInterval
  let source: NarrationSource?
  let locale: Locale
  let languageCode: String?
  let ebookURL: URL?
  let ebookLocation: String?
  let ebookProgress: Double?

  var isDownloaded: Bool { source != nil }

  var hasEbook: Bool { ebookURL != nil }

  @MainActor
  init(localBook: LocalBook) {
    let progress = try? MediaProgress.fetch(bookID: localBook.bookID)

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
    ebookLocation = progress?.ebookLocation
    ebookProgress = progress?.ebookProgress
  }
}
