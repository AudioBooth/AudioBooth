import API
import AppIntents
import CoreSpotlight
import Foundation
import Logging
import Models
import PlayerIntents

enum AudiobookIndexer {
  static func populate() {
    guard #available(iOS 18.0, *) else {
      AppLogger.player.info("Siri indexing skipped: iOS < 18")
      return
    }

    Task {
      let books = ((try? LocalBook.fetchAll()) ?? [])
        .filter { $0.mediaType.contains(.audiobook) }

      let entities = books.map { book in
        AudiobookEntity(
          id: book.bookID,
          title: book.title,
          seriesTitle: book.series.first?.name,
          author: book.authorNames.isEmpty ? nil : book.authorNames,
          genre: book.genres?.first,
          purchaseDate: book.createdAt
        )
      }

      AppLogger.player.info("Siri indexing started: \(entities.count) audiobooks")

      do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
        AppLogger.player.info("Siri indexing succeeded: \(entities.count) audiobooks")
      } catch {
        AppLogger.player.error("Siri indexing failed: \(error.localizedDescription)")
      }
    }
  }
}
