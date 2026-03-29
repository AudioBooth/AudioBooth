import CarPlay
import Combine
import Foundation
import Models
import Nuke

final class CarPlayOffline: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var currentPlayerCancellable: AnyCancellable?
  private let downloadManager = DownloadManager.shared

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    let title = String(localized: "Offline")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "arrow.down.circle.fill")

    currentPlayerCancellable = PlayerManager.shared.$current.sink { [weak self] _ in
      Task {
        await self?.loadContent()
      }
    }

    Task {
      await loadContent()
    }
  }

  func willAppear() {
    Task { await loadContent() }
  }

  private func loadContent() async {
    var sections: [CPListSection] = []

    let bookItems = await buildBookItems()
    if !bookItems.isEmpty {
      sections.append(CPListSection(items: bookItems, header: String(localized: "Books"), sectionIndexTitle: nil))
    }

    let episodeItems = await buildEpisodeItems()
    if !episodeItems.isEmpty {
      sections.append(CPListSection(items: episodeItems, header: String(localized: "Episodes"), sectionIndexTitle: nil))
    }

    if sections.isEmpty {
      template.updateSections([])
      template.emptyViewTitleVariants = [
        String(localized: "No offline content")
      ]
    } else {
      template.updateSections(sections)
    }
  }

  private func buildBookItems() async -> [CPListItem] {
    do {
      let offlineBooks = try LocalBook.fetchAll()
        .filter({ downloadManager.downloadStates[$0.bookID] == .downloaded && $0.duration > 0 })
        .sorted()

      return offlineBooks.map { localBook in
        createListItem(for: localBook)
      }
    } catch {
      return []
    }
  }

  private func createListItem(for localBook: LocalBook) -> CPListItem {
    let item = CPListItem(
      text: localBook.title,
      detailText: localBook.authorNames
    )

    item.isPlaying = localBook.bookID == PlayerManager.shared.current?.id

    if let coverURL = localBook.coverURL {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onBookSelected(bookID: localBook.bookID, completion: completion)
    }

    return item
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }

  private func onBookSelected(bookID: String, completion: @escaping () -> Void) {
    guard let book = try? LocalBook.fetch(bookID: bookID) else {
      completion()
      return
    }

    Task {
      PlayerManager.shared.setCurrent(book)
      try? await Task.sleep(for: .milliseconds(500))
      PlayerManager.shared.play()
      nowPlaying?.showNowPlaying()
      completion()
    }
  }

  private func buildEpisodeItems() async -> [CPListItem] {
    do {
      let offlineEpisodes = try LocalEpisode.fetchAll()
        .filter { downloadManager.downloadStates[$0.episodeID] == .downloaded && $0.duration > 0 }
        .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

      return offlineEpisodes.map { episode in
        createListItem(for: episode)
      }
    } catch {
      return []
    }
  }

  private func createListItem(for episode: LocalEpisode) -> CPListItem {
    let item = CPListItem(
      text: episode.title,
      detailText: episode.podcast?.title
    )

    item.isPlaying = episode.episodeID == PlayerManager.shared.current?.id

    if let coverURL = episode.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onEpisodeSelected(episodeID: episode.episodeID, completion: completion)
    }

    return item
  }

  private func onEpisodeSelected(episodeID: String, completion: @escaping () -> Void) {
    guard let episode = try? LocalEpisode.fetch(episodeID: episodeID) else {
      completion()
      return
    }

    Task {
      PlayerManager.shared.setCurrent(episode)
      try? await Task.sleep(for: .milliseconds(500))
      PlayerManager.shared.play()
      nowPlaying?.showNowPlaying()
      completion()
    }
  }
}
