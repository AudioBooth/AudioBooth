import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayLibrary {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?

  enum FilterType {
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
    let filter: String

    switch filterType {
    case .series(let series):
      let base64SeriesID = Data(series.id.utf8).base64EncodedString()
      filter = "series.\(base64SeriesID)"
    case .author(let author):
      let base64AuthorID = Data(author.id.utf8).base64EncodedString()
      filter = "authors.\(base64AuthorID)"
    }

    do {
      let page = try await Audiobookshelf.shared.books.fetch(filter: filter)
      let items = page.results.map { book in
        createListItem(for: book)
      }
      let section = CPListSection(items: items)
      template.updateSections([section])
    } catch {
      template.updateSections([])
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

    if case .series(let series) = filterType, let sequence = book.series?.first(where: { $0.id == series.id })?.sequence
    {
      details.append("#\(sequence)")
    }

    if let publishedYear = book.publishedYear {
      details.append(publishedYear)
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
