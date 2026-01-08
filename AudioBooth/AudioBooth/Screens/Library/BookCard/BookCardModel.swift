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

    contextMenu = BookCardContextMenuModel(
      item,
      onProgressChanged: { [weak self] progress in
        self?.progress = progress
      }
    )
  }

  init(
    _ item: Book,
    sortBy: BooksService.SortBy?,
    navigate: ((NavigationDestination) -> Void)? = nil
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

      let time: Date.FormatStyle.TimeStyle
      if UserPreferences.shared.libraryDisplayMode == .row {
        time = .shortened
      } else {
        time = .omitted
      }

      switch sortBy {
      case .publishedYear:
        details = item.publishedYear.map({ "Published \($0)" })
      case .title, .authorName, .authorNameLF:
        details = nil
      case .addedAt:
        details =
          "Added \(item.addedAt.formatted(date: .numeric, time: time))"
      case .updatedAt:
        details =
          "Updated \(item.updatedAt.formatted(date: .numeric, time: time))"
      case .size:
        details = item.size.map {
          "Size \($0.formatted(.byteCount(style: .file)))"
        }
      case .duration:
        details = Duration.seconds(item.duration).formatted(
          .units(
            allowed: [.hours, .minutes, .seconds],
            width: .narrow
          )
        )
      case .progress:
        if let mediaProgress = try? MediaProgress.fetch(bookID: item.id) {
          details = "Progress: \(mediaProgress.lastUpdate.formatted(date: .numeric, time: time))"
        } else {
          details = nil
        }
      case .progressFinishedAt:
        if let mediaProgress = try? MediaProgress.fetch(bookID: item.id), mediaProgress.isFinished {
          details = "Finished \(mediaProgress.lastUpdate.formatted(date: .numeric, time: time))"
        } else {
          details = nil
        }
      case .progressCreatedAt:
        if let mediaProgress = try? MediaProgress.fetch(bookID: item.id) {
          details = "Started \(mediaProgress.lastPlayedAt.formatted(date: .numeric, time: time))"
        } else {
          details = nil
        }
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
      coverURL: item.coverURL(),
      sequence: sequence,
      author: author,
      narrator: narrator,
      publishedYear: publishedYear,
      downloadProgress: nil,
      bookCount: bookCount
    )

    setupDownloadProgressObserver()

    contextMenu = BookCardContextMenuModel(
      item,
      onProgressChanged: { [weak self] progress in
        self?.progress = progress
      }
    )
  }

  private func setupDownloadProgressObserver() {
    downloadStateCancellable = DownloadManager.shared.$downloadStates
      .sink { [weak self] states in
        guard let self else { return }
        if case .downloading(let progress) = states[self.id] {
          self.downloadProgress = progress
        } else {
          self.downloadProgress = nil
        }
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
}
