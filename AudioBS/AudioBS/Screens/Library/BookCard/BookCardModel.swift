import API
import Foundation
import Models

final class BookCardModel: BookCard.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
  }
  private let item: Item

  init(_ item: LocalBook) {
    let id = item.bookID

    self.item = .local(item)

    let narrator = item.narrators.isEmpty ? nil : item.narrators.joined(separator: ", ")

    super.init(
      id: id,
      title: item.title,
      details: item.authorNames,
      coverURL: item.coverURL,
      sequence: item.series.first?.sequence,
      author: item.authorNames,
      narrator: narrator,
      publishedYear: item.publishedYear
    )
  }

  init(_ item: Book, sortBy: BooksService.SortBy?) {
    let id = item.id

    let details: String?
    switch sortBy {
    case .publishedYear:
      details = item.publishedYear.map({ "Published \($0)" })
    case .title, .authorName, .authorNameLF:
      details = item.authorName
    case .addedAt:
      details =
        "Added \(DateFormatter.localizedString(from: item.addedAt, dateStyle: .short, timeStyle: .none))"
    case .updatedAt:
      details =
        "Updated \(DateFormatter.localizedString(from: item.updatedAt, dateStyle: .short, timeStyle: .none))"
    case .size:
      details = item.size.map {
        "Size \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))"
      }
    case .duration:
      details = Duration.seconds(item.duration).formatted(
        .units(
          allowed: [.hours, .minutes, .seconds],
          width: .narrow
        )
      )
    case nil:
      details = nil
    }

    self.item = .remote(item)

    super.init(
      id: id,
      title: item.title,
      details: details,
      coverURL: item.coverURL,
      sequence: item.series?.first?.sequence,
      author: item.authorName,
      narrator: item.media.metadata.narratorName,
      publishedYear: item.publishedYear
    )
  }

  override func onAppear() {
    progress = try? MediaProgress.fetch(bookID: id)?.progress
  }
}
