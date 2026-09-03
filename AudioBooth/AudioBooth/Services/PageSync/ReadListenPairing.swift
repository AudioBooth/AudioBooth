import API
import Foundation

/// The audiobook and ebook items of one title, whichever library items they live in.
struct ReadListenPair {
  let audiobook: Book?
  let ebook: Book?

  var isComplete: Bool { audiobook != nil && ebook != nil }
}

/// Resolves and caches, for the app session, which formats a title has in the library.
enum ReadListenPairing {
  private static var cache: [String: ReadListenPair] = [:]

  static func cached(for itemID: String) -> ReadListenPair? {
    cache[itemID]
  }

  static func resolve(for book: Book) async -> ReadListenPair {
    if let cached = cache[book.id] {
      return cached
    }

    let audiobook = try? await LibraryItemPairing.audiobookItem(for: book)
    let ebook = try? await LibraryItemPairing.ebookItem(for: book)
    let pair = ReadListenPair(audiobook: audiobook, ebook: ebook)

    cache[book.id] = pair
    if let audiobook {
      cache[audiobook.id] = pair
    }
    if let ebook {
      cache[ebook.id] = pair
    }
    return pair
  }

  static func resolve(itemID: String) async -> ReadListenPair? {
    if let cached = cache[itemID] {
      return cached
    }
    guard let book = try? await Audiobookshelf.shared.books.fetch(id: itemID) else { return nil }
    return await resolve(for: book)
  }
}
