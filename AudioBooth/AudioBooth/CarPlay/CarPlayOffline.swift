import CarPlay
import Combine
import Foundation
import Models
import Nuke

final class CarPlayOffline {
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
        await self?.loadBooks()
      }
    }

    Task {
      await loadBooks()
    }
  }

  private func loadBooks() async {
    let items = await buildBookItems()
    if items.isEmpty {
      template.updateSections([])
      template.emptyViewTitleVariants = [
        String(localized: "No offline books")
      ]
    } else {
      let section = CPListSection(items: items)
      template.updateSections([section])
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

      nowPlaying?.showNowPlaying()
      completion()
    }
  }
}
