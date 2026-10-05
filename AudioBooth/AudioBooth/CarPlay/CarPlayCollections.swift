import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayCollections {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private let mode: CollectionMode
  private var selectedDetail: CarPlayCollectionDetails?
  private let itemsPerPage: Int = 50

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying, mode: CollectionMode) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying
    self.mode = mode

    let title =
      switch mode {
      case .collections: String(localized: "Collections")
      case .playlists: String(localized: "Playlists")
      }
    template = CPListTemplate(title: title, sections: [])
    template.emptyViewTitleVariants = [String(localized: "Loading...")]

    Task { await load() }
  }

  private func load() async {
    let items: [CPListItem]

    switch mode {
    case .collections:
      let page = try? await Audiobookshelf.shared.collections.fetch(limit: itemsPerPage, page: 0)
      items = (page?.results ?? []).map {
        createListItem(id: $0.id, name: $0.name, count: $0.itemCount, coverURL: $0.covers.first)
      }
    case .playlists:
      let page = try? await Audiobookshelf.shared.playlists.fetch(limit: itemsPerPage, page: 0)
      items = (page?.results ?? []).map {
        createListItem(id: $0.id, name: $0.name, count: $0.itemCount, coverURL: $0.covers.first)
      }
    }

    guard !items.isEmpty else {
      template.emptyViewTitleVariants = [
        mode == .collections ? String(localized: "No Collections") : String(localized: "No Playlists")
      ]
      template.emptyViewSubtitleVariants = [String(localized: "Create collections or playlists in the app")]
      return
    }

    template.updateSections([CPListSection(items: items)])
  }

  private func createListItem(id: String, name: String, count: Int, coverURL: URL?) -> CPListItem {
    let item = CPListItem(
      text: name,
      detailText: "\(count) item\(count == 1 ? "" : "s")"
    )

    if let coverURL {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.showDetails(id: id, name: name)
      completion()
    }

    return item
  }

  private func showDetails(id: String, name: String) {
    guard let nowPlaying else { return }
    let details = CarPlayCollectionDetails(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      id: id,
      name: name,
      mode: mode
    )
    selectedDetail = details
    interfaceController.pushTemplate(details.template, animated: true, completion: nil)
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}
