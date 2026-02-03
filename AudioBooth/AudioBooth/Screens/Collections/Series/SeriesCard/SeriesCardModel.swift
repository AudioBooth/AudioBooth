import API
import Models
import SwiftUI

final class SeriesCardModel: SeriesCard.Model {
  init(series: API.Series, sortingIgnorePrefix: Bool = false) {
    let bookCovers = series.books.prefix(10).map { book in
      Cover.Model(
        url: book.coverURL(),
        title: book.title,
        author: book.authorName
      )
    }
    let progress = Self.progress(books: series.books)

    let title: String
    if sortingIgnorePrefix {
      title = series.nameIgnorePrefix ?? series.name
    } else {
      title = series.name
    }

    super.init(
      id: series.id,
      title: title,
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
