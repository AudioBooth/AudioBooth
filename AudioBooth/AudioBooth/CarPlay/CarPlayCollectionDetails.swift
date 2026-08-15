import API
@preconcurrency import CarPlay
import Foundation
import Models
import Nuke

final class CarPlayCollectionDetails {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private let id: String
  private let mode: CollectionMode
  private var items: [QueueItem] = []
  private var loadingTask: Task<Void, Never>?
  private var loadTask: Task<Void, Never>?

  let template: CPListTemplate

  init(
    interfaceController: CPInterfaceController,
    nowPlaying: CarPlayNowPlaying,
    id: String,
    name: String,
    mode: CollectionMode
  ) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying
    self.id = id
    self.mode = mode

    template = CPListTemplate(title: name, sections: [])
    template.emptyViewTitleVariants = [String(localized: "Loading...")]

    loadTask = Task { await load() }
  }

  private func load() async {
    switch mode {
    case .collections:
      let collection = try? await Audiobookshelf.shared.collections.fetch(id: id)
      items = collection?.queueItems ?? []
    case .playlists:
      let playlist = try? await Audiobookshelf.shared.playlists.fetch(id: id)
      items = playlist?.queueItems ?? []
    }

    guard !Task.isCancelled else { return }

    buildSections()
  }

  private func buildSections() {
    guard !items.isEmpty else {
      template.emptyViewTitleVariants = [String(localized: "No Items")]
      return
    }

    let playAllItem = CPListItem(
      text: String(localized: "Play All"),
      detailText: "\(items.count) item\(items.count == 1 ? "" : "s")"
    )
    playAllItem.setImage(UIImage(systemName: "play.fill"))
    playAllItem.handler = { [weak self] _, completion in
      self?.onPlayAll()
      completion()
    }

    let trackItems = items.enumerated().map { index, queueItem in
      createListItem(for: queueItem, index: index)
    }

    let playAllSection = CPListSection(items: [playAllItem])
    let tracksSection = CPListSection(items: trackItems)
    template.updateSections([playAllSection, tracksSection])
  }

  private func createListItem(for queueItem: QueueItem, index: Int) -> CPListItem {
    let item = CPListItem(
      text: queueItem.title,
      detailText: queueItem.details
    )

    item.isPlaying = queueItem.bookID == PlayerManager.shared.current?.id

    if let coverURL = queueItem.coverURL {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onItemSelected(from: index)
      completion()
    }

    return item
  }

  private func onPlayAll() {
    loadingTask?.cancel()
    let notCompleted = items.filter { MediaProgress.progress(for: $0.bookID) < 1.0 }
    let playlist = notCompleted.isEmpty ? items : notCompleted
    loadingTask = Task {
      PlayerManager.shared.playAll(playlist)
      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))
      nowPlaying?.showNowPlaying()
      loadingTask = nil
    }
  }

  private func onItemSelected(from index: Int) {
    loadingTask?.cancel()
    loadingTask = Task {
      let remaining = Array(items[index...])
      PlayerManager.shared.playAll(remaining)
      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))
      nowPlaying?.showNowPlaying()
      loadingTask = nil
    }
  }

  private func waitForPlayerReady() async {
    guard PlayerManager.shared.current?.isLoading == true else { return }

    await withCheckedContinuation { continuation in
      observePlayerLoading(continuation: continuation)
    }
  }

  private func observePlayerLoading(continuation: CheckedContinuation<Void, Never>) {
    withObservationTracking {
      _ = PlayerManager.shared.current?.isLoading
    } onChange: {
      RunLoop.main.perform {
        if PlayerManager.shared.current?.isLoading == false {
          continuation.resume()
        } else {
          self.observePlayerLoading(continuation: continuation)
        }
      }
    }
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
