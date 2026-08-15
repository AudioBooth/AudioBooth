import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayCollections: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var selectedDetail: CarPlayCollectionDetails?

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
        createListItem(name: $0.name, count: $0.itemCount, coverURL: $0.covers.first, queueItems: $0.queueItems)
      }
      sections.append(CPListSection(items: items, header: String(localized: "Collections"), sectionIndexTitle: nil))
    }

    if !playlists.isEmpty {
      let items = playlists.map {
        createListItem(name: $0.name, count: $0.itemCount, coverURL: $0.covers.first, queueItems: $0.queueItems)
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
    try? await Audiobookshelf.shared.collections.fetch()
  }

  private func fetchPlaylists() async -> Page<Playlist>? {
    try? await Audiobookshelf.shared.playlists.fetch()
  }

  private func createListItem(name: String, count: Int, coverURL: URL?, queueItems: [QueueItem]) -> CPListItem {
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
      self?.showDetails(name: name, items: queueItems)
      completion()
    }

    return item
  }

  private func showDetails(name: String, items: [QueueItem]) {
    guard let nowPlaying else { return }
    let details = CarPlayCollectionDetails(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      name: name,
      items: items
    )
    selectedDetail = details
    interfaceController.pushTemplate(details.template, animated: true, completion: nil)
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}

private extension Collection {
  var queueItems: [QueueItem] {
    books.map {
      QueueItem(bookID: $0.id, title: $0.title, details: $0.authorName, coverURL: $0.coverURL())
    }
  }
}

private extension Playlist {
  var queueItems: [QueueItem] {
    items.compactMap { item in
      switch item.libraryItem {
      case .book(let book):
        return QueueItem(bookID: book.id, title: book.title, details: book.authorName, coverURL: book.coverURL())
      case .podcast(let podcast):
        guard let episodeID = item.episodeID else { return nil }
        let title = item.episode?.title ?? podcast.title
        return QueueItem(
          bookID: episodeID,
          title: title,
          details: podcast.title,
          coverURL: podcast.coverURL(),
          podcastID: podcast.id
        )
      }
    }
  }
}
