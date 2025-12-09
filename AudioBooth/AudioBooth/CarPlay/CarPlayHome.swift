import API
@preconcurrency import CarPlay
import Combine
import Foundation
import Nuke

final class CarPlayHome {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var currentPlayerCancellable: AnyCancellable?
  private var selected: CarPlayLibrary?

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    template = CPListTemplate(title: "Home", sections: [])
    template.tabTitle = "Home"
    template.tabImage = UIImage(systemName: "house.fill")

    currentPlayerCancellable = PlayerManager.shared.$current.sink { [weak self] _ in
      Task {
        await self?.loadSections()
      }
    }
  }

  private func loadSections() async {
    let sections = await buildSections()
    template.updateSections(sections)
  }

  private func buildSections() async -> [CPListSection] {
    var sections: [CPListSection] = []

    if let continueListeningSection = await buildContinueListeningSection() {
      sections.append(continueListeningSection)
    }

    let bookSections = await buildBookSections()
    sections.append(contentsOf: bookSections)

    let seriesSections = await buildSeriesSections()
    sections.append(contentsOf: seriesSections)

    let authorSections = await buildAuthorSections()
    sections.append(contentsOf: authorSections)

    if sections.isEmpty {
      template.emptyViewTitleVariants = ["No Content"]
      template.emptyViewSubtitleVariants = ["Your library content will appear here"]
    }

    return sections
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }

  private func onBookSelected(_ book: Book) {
    PlayerManager.shared.setCurrent(book)
    nowPlaying?.showNowPlaying()
  }

  private func showLibrary(filterType: CarPlayLibrary.FilterType) {
    guard let nowPlaying else { return }
    let library = CarPlayLibrary(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      filterType: filterType
    )
    selected = library
    interfaceController.pushTemplate(library.template, animated: true, completion: nil)
  }
}

extension CarPlayHome {
  private func buildContinueListeningSection() async -> CPListSection? {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return nil
    }

    guard let continueListeningData = personalized.sections.first(where: { $0.id == "continue-listening" }) else {
      return nil
    }

    guard case .books(let books) = continueListeningData.entities, !books.isEmpty else {
      return nil
    }

    let items = books.map { book in
      createListItem(for: book)
    }

    return CPListSection(items: items, header: "Continue Listening", sectionIndexTitle: nil)
  }

  private func buildBookSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard section.id != "continue-listening",
        case .books(let books) = section.entities,
        !books.isEmpty
      else {
        continue
      }

      let items = books.map { book in
        createListItem(for: book)
      }

      sections.append(CPListSection(items: items, header: section.label, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildSeriesSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard case .series(let seriesList) = section.entities, !seriesList.isEmpty else {
        continue
      }

      let items = seriesList.map { series in
        createListItem(for: series)
      }

      sections.append(CPListSection(items: items, header: section.label, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildAuthorSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard case .authors(let authors) = section.entities, !authors.isEmpty else {
        continue
      }

      let items = authors.map { author in
        createListItem(for: author)
      }

      sections.append(CPListSection(items: items, header: section.label, sectionIndexTitle: nil))
    }

    return sections
  }

  private func createListItem(for book: Book) -> CPListItem {
    let item = CPListItem(
      text: book.title,
      detailText: book.authorName
    )

    item.isPlaying = book.id == PlayerManager.shared.current?.id

    if let coverURL = book.coverURL {
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

  private func createListItem(for series: Series) -> CPListItem {
    let bookCount = series.books.count
    let item = CPListItem(
      text: series.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    if let firstBook = series.books.first, let coverURL = firstBook.coverURL {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.showLibrary(filterType: .series(series))
      completion()
    }

    return item
  }

  private func createListItem(for author: Author) -> CPListItem {
    let bookCount = author.numBooks ?? 0
    let item = CPListItem(
      text: author.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    item.handler = { [weak self] _, completion in
      self?.showLibrary(filterType: .author(author))
      completion()
    }

    return item
  }
}
