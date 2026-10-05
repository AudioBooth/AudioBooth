@preconcurrency import CarPlay
import Foundation

final class CarPlayLibraryTab: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var selected: AnyObject?

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    let title = String(localized: "Library")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "square.stack.fill")

    let items = [
      createItem(title: String(localized: "Books")) { [weak self] in
        self?.showBooks()
      },
      createItem(title: String(localized: "Series")) { [weak self] in
        self?.showSeries()
      },
      createItem(title: String(localized: "Collections")) { [weak self] in
        self?.showCollections(mode: .collections)
      },
      createItem(title: String(localized: "Playlists")) { [weak self] in
        self?.showCollections(mode: .playlists)
      },
    ]
    template.updateSections([CPListSection(items: items)])
  }

  func willAppear() {}

  private func createItem(title: String, action: @escaping () -> Void) -> CPListItem {
    let item = CPListItem(text: title, detailText: nil)
    item.accessoryType = .disclosureIndicator
    item.handler = { _, completion in
      action()
      completion()
    }
    return item
  }

  private func showBooks() {
    guard let nowPlaying else { return }
    let library = CarPlayLibrary(interfaceController: interfaceController, nowPlaying: nowPlaying, filterType: .all)
    push(library, template: library.template)
  }

  private func showSeries() {
    guard let nowPlaying else { return }
    let series = CarPlaySeries(interfaceController: interfaceController, nowPlaying: nowPlaying)
    push(series, template: series.template)
  }

  private func showCollections(mode: CollectionMode) {
    guard let nowPlaying else { return }
    let collections = CarPlayCollections(interfaceController: interfaceController, nowPlaying: nowPlaying, mode: mode)
    push(collections, template: collections.template)
  }

  private func push(_ page: AnyObject, template: CPTemplate) {
    selected = page
    interfaceController.pushTemplate(template, animated: true, completion: nil)
  }
}
