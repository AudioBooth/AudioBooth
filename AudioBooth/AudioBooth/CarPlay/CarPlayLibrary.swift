import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayLibrary {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?

  enum FilterType {
    case all
    case series(Series)
    case author(Author)
  }

  let template: CPListTemplate
  private let filterType: FilterType

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying, filterType: FilterType) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying
    self.filterType = filterType

    let title: String
    switch filterType {
    case .all:
      title = String(localized: "Books")
    case .series(let series):
      title = series.name
    case .author(let author):
      title = author.name
    }

    template = CPListTemplate(title: title, sections: [])

    Task {
      await loadBooks()
    }
  }

  private func loadBooks() async {
    do {
      let page = try await fetchBooks()
      let items = page.results.map { book in
        createListItem(for: book)
      }
      template.updateSections(makeSections(items: items, total: page.total))
    } catch {
      template.updateSections([])
    }
  }

  private func makeSections(items: [CPListItem], total: Int) -> [CPListSection] {
    guard case .all = filterType else { return [CPListSection(items: items)] }

    let header = "\(total) book\(total == 1 ? "" : "s")"
    return [CPListSection(items: items, header: header, sectionIndexTitle: nil)]
  }

  private func fetchBooks() async throws -> Page<Book> {
    switch filterType {
    case .all:
      let preferences = UserPreferences.shared
      return try await Audiobookshelf.shared.books.fetch(
        limit: 100,
        sortBy: preferences.librarySortBy,
        ascending: preferences.librarySortAscending
      )
    case .series(let series):
      let base64SeriesID = Data(series.id.utf8).base64EncodedString()
      return try await Audiobookshelf.shared.books.fetch(filter: "series.\(base64SeriesID)")
    case .author(let author):
      let base64AuthorID = Data(author.id.utf8).base64EncodedString()
      return try await Audiobookshelf.shared.books.fetch(filter: "authors.\(base64AuthorID)")
    }
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }

  private func onBookSelected(_ book: Book) {
    PlayerManager.shared.setCurrent(book)
    PlayerManager.shared.play()
    nowPlaying?.showNowPlaying()
  }

  private func createListItem(for book: Book) -> CPListItem {
    var details = [String]()

    switch filterType {
    case .all:
      if let authorName = book.authorName {
        details.append(authorName)
      }
      let sortBy = UserPreferences.shared.librarySortBy
      if let sortDetails = book.sortDetails(for: sortBy, time: .omitted) {
        details.append(sortDetails)
      }
    case .series(let series):
      if let sequence = book.series?.first(where: { $0.id == series.id })?.sequence {
        details.append("#\(sequence)")
      }
      if let publishedYear = book.publishedYear {
        details.append(publishedYear)
      }
    case .author:
      if let publishedYear = book.publishedYear {
        details.append(publishedYear)
      }
    }

    let detailText: String? = details.isEmpty ? nil : details.joined(separator: " • ")

    let item = CPListItem(
      text: book.title,
      detailText: detailText
    )

    item.isPlaying = book.id == PlayerManager.shared.current?.id

    if let coverURL = book.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onBookSelected(book)
      completion()
    }

    return item
  }
}
