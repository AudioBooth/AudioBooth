import API
import Models
import SwiftUI

final class SeriesCardModel: SeriesCard.Model {
  init(series: API.Series) {
    let bookCovers = series.books.prefix(10).map(\.coverURL)
    let progress = Self.progress(books: series.books)

    super.init(
      id: series.id,
      title: series.name,
      bookCount: series.books.count,
      bookCovers: Array(bookCovers),
      progress: progress
    )
  }

  static func progress(books: [Book]) -> Double? {
    guard !books.isEmpty else { return nil }

    let totalProgress = books.compactMap { book in
      MediaProgress.progress(for: book.id)
    }.reduce(0, +)

    return totalProgress / Double(books.count)
  }
}
