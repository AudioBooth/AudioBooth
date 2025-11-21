import API
import Combine
import Foundation
import Models

final class BookCardModel: BookCard.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
  }
  private let item: Item
  private let navigate: ((NavigationDestination) -> Void)?
  private var downloadStateCancellable: AnyCancellable?

  init(_ item: LocalBook, navigate: ((NavigationDestination) -> Void)? = nil) {
    let id = item.bookID

    self.item = .local(item)
    self.navigate = navigate

    let narrator = item.narrators.isEmpty ? nil : item.narrators.joined(separator: ", ")

    super.init(
      id: id,
      title: item.title,
      details: item.authorNames,
      coverURL: item.coverURL,
      sequence: item.series.first?.sequence,
      author: item.authorNames,
      narrator: narrator,
      publishedYear: item.publishedYear,
      downloadProgress: nil
    )

    setupDownloadProgressObserver()
  }

  init(
    _ item: Book, sortBy: BooksService.SortBy?, navigate: ((NavigationDestination) -> Void)? = nil
  ) {
    let id: String
    let title: String
    let bookCount: Int?
    let details: String?
    let sequence: String?
    let author: String?
    let narrator: String?
    let publishedYear: String?

    if let collapsedSeries = item.collapsedSeries {
      id = collapsedSeries.id
      title = collapsedSeries.name
      bookCount = collapsedSeries.numBooks
      details = nil
      sequence = nil
      author = nil
      narrator = nil
      publishedYear = nil
    } else {
      id = item.id
      title = item.title
      sequence = item.series?.first?.sequence
      author = item.authorName
      narrator = item.media.metadata.narratorName
      publishedYear = item.publishedYear
      bookCount = nil

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
    }

    self.item = .remote(item)
    self.navigate = navigate

    super.init(
      id: id,
      title: title,
      details: details,
      coverURL: item.coverURL,
      sequence: sequence,
      author: author,
      narrator: narrator,
      publishedYear: publishedYear,
      downloadProgress: nil,
      bookCount: bookCount
    )

    setupDownloadProgressObserver()
  }

  private func setupDownloadProgressObserver() {
    downloadStateCancellable = DownloadManager.shared.$currentProgress
      .sink { [weak self] progressDict in
        guard let self else { return }
        self.downloadProgress = progressDict[self.id]
      }
  }

  override func onAppear() {
    if case .remote(let book) = item, let collapsedSeries = book.collapsedSeries {
      progress = Self.calculateSeriesProgress(libraryItemIds: collapsedSeries.libraryItemIds)
    } else {
      progress = MediaProgress.progress(for: id)
    }
  }

  private static func calculateSeriesProgress(libraryItemIds: [String]) -> Double? {
    guard !libraryItemIds.isEmpty else { return nil }

    let totalProgress = libraryItemIds.compactMap { bookID in
      MediaProgress.progress(for: bookID)
    }.reduce(0, +)

    return totalProgress / Double(libraryItemIds.count)
  }

  override func contextMenu() -> BookCardContextMenu.Model {
    switch item {
    case .local(let localBook):
      BookCardContextMenuModel(
        localBook,
        onProgressChanged: { [weak self] progress in
          self?.progress = progress
        })
    case .remote(let book):
      BookCardContextMenuModel(
        book,
        onProgressChanged: { [weak self] progress in
          self?.progress = progress
        })
    }
  }
}
