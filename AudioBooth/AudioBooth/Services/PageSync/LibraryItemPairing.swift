import API
import Foundation
import Logging

/// Audiobookshelf libraries often keep the audiobook and the ebook of a title as separate
/// items. These helpers find the counterpart of an item by title and author.
enum LibraryItemPairing {
  /// The item providing the ebook text for `book`: itself when it has one, otherwise an
  /// ebook-only item with the same title.
  static func ebookItem(for book: Book) async throws -> Book? {
    if book.mediaType.contains(.ebook) { return book }
    return try await counterpart(of: book, requiring: .ebook)
  }

  /// The item providing the audio for `book`: itself when it has audio, otherwise an
  /// audiobook item with the same title.
  static func audiobookItem(for book: Book) async throws -> Book? {
    if book.mediaType.contains(.audiobook) { return book }
    return try await counterpart(of: book, requiring: .audiobook)
  }

  private static func counterpart(of book: Book, requiring type: Book.MediaType) async throws -> Book? {
    let wantedTitle = comparableTitle(book.title)
    let wantedAuthor = book.authorName.map { PageTextNormalizer.normalize($0) }

    let response = try await Audiobookshelf.shared.search.search(query: searchQuery(for: book.title), limit: 25)
    let candidates = response.book
      .map(\.libraryItem)
      .filter { $0.id != book.id && $0.mediaType.contains(type) }

    func score(_ candidate: Book) -> Int {
      let title = comparableTitle(candidate.title)
      var score = 0
      if title == wantedTitle {
        score += 4
      } else if title.hasPrefix(wantedTitle) || wantedTitle.hasPrefix(title) {
        score += 2
      } else {
        return 0
      }
      if let wantedAuthor, let author = candidate.authorName.map({ PageTextNormalizer.normalize($0) }),
        author == wantedAuthor
      {
        score += 1
      }
      return score
    }

    let match = candidates.map { ($0, score($0)) }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    if let match {
      AppLogger.viewModel.info("Page Sync: paired \"\(book.title)\" with \"\(match.title)\" (\(match.id))")
    }
    return match
  }

  /// "Pachinko (National Book Award Finalist)" -> "pachinko"
  private static func comparableTitle(_ title: String) -> String {
    PageTextNormalizer.normalize(baseTitle(title))
  }

  private static func searchQuery(for title: String) -> String {
    let base = baseTitle(title).trimmingCharacters(in: .whitespacesAndNewlines)
    return base.isEmpty ? title : base
  }

  private static func baseTitle(_ title: String) -> String {
    var value = title
    for separator in [" (", " [", ":"] {
      if let range = value.range(of: separator) {
        value = String(value[..<range.lowerBound])
      }
    }
    return value
  }
}
