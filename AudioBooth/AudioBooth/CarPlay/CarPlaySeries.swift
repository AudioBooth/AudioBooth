import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlaySeries {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var selected: CarPlayLibrary?
  private let itemsPerPage: Int = 50

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    template = CPListTemplate(title: String(localized: "Series"), sections: [])
    template.emptyViewTitleVariants = [String(localized: "Loading...")]

    Task { await load() }
  }

  private func load() async {
    let page = try? await Audiobookshelf.shared.series.fetch(
      limit: itemsPerPage,
      page: 0,
      sortBy: .name,
      ascending: true
    )
    let series = page?.results ?? []

    guard let page, !series.isEmpty else {
      template.emptyViewTitleVariants = [String(localized: "No Series Found")]
      template.emptyViewSubtitleVariants = [
        String(localized: "Your library appears to have no series or no library is selected.")
      ]
      return
    }

    let items = series.map { createListItem(for: $0) }
    let seriesSection = CPListSection(items: items, header: "\(page.total) series", sectionIndexTitle: nil)
    template.updateSections([seriesSection])
  }

  private func createListItem(for series: Series) -> CPListItem {
    let bookCount = series.books.count
    let item = CPListItem(
      text: series.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    if let coverURL = series.books.first?.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.showLibrary(for: series)
      completion()
    }

    return item
  }

  private func showLibrary(for series: Series) {
    guard let nowPlaying else { return }
    let library = CarPlayLibrary(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      filterType: .series(series)
    )
    selected = library
    interfaceController.pushTemplate(library.template, animated: true, completion: nil)
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}
