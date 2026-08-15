import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayCollections: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var selectedDetail: CarPlayCollectionDetails?
  private let itemsPerPage: Int = 20

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    let title = String(localized: "Collections")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "square.stack.fill")
    template.emptyViewTitleVariants = [String(localized: "Loading...")]
  }

  func willAppear() {
    Task { await load() }
  }

  private func load() async {
    async let collectionsResult = fetchCollections()
    async let playlistsResult = fetchPlaylists()

    let (collectionsPage, playlistsPage) = await (collectionsResult, playlistsResult)

    let collections = collectionsPage?.results ?? []
    let playlists = playlistsPage?.results ?? []

    var sections: [CPListSection] = []

    if !collections.isEmpty {
      let items = collections.map {
        createListItem(id: $0.id, name: $0.name, count: $0.itemCount, coverURL: $0.covers.first, mode: .collections)
      }
      sections.append(CPListSection(items: items, header: String(localized: "Collections"), sectionIndexTitle: nil))
    }

    if !playlists.isEmpty {
      let items = playlists.map {
        createListItem(id: $0.id, name: $0.name, count: $0.itemCount, coverURL: $0.covers.first, mode: .playlists)
      }
      sections.append(CPListSection(items: items, header: String(localized: "Playlists"), sectionIndexTitle: nil))
    }

    if sections.isEmpty {
      template.emptyViewTitleVariants = [String(localized: "No Collections")]
      template.emptyViewSubtitleVariants = [String(localized: "Create collections or playlists in the app")]
    }

    template.updateSections(sections)
  }

  private func fetchCollections() async -> Page<Collection>? {
    try? await Audiobookshelf.shared.collections.fetch(limit: itemsPerPage, page: 0)
  }

  private func fetchPlaylists() async -> Page<Playlist>? {
    try? await Audiobookshelf.shared.playlists.fetch(limit: itemsPerPage, page: 0)
  }

  private func createListItem(id: String, name: String, count: Int, coverURL: URL?, mode: CollectionMode) -> CPListItem
  {
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
      self?.showDetails(id: id, name: name, mode: mode)
      completion()
    }

    return item
  }

  private func showDetails(id: String, name: String, mode: CollectionMode) {
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
