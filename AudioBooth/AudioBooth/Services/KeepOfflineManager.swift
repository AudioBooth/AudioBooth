import API
import Combine
import Foundation
import Logging
import Models
import Network

final class KeepOfflineManager {
  static let shared = KeepOfflineManager()

  static let counts = [1, 2, 3, 5, 10]

  private let preferences = UserPreferences.shared
  private let downloadManager = DownloadManager.shared
  private var cancellables = Set<AnyCancellable>()
  private var isReconciling = false

  private init() {
    PlayerManager.shared.$current
      .removeDuplicates { $0?.id == $1?.id }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.reconcile()
      }
      .store(in: &cancellables)
  }

  func reconcile() {
    guard Audiobookshelf.shared.authentication.isAuthenticated, !isReconciling else { return }

    guard isNetworkAllowed else {
      AppLogger.download.debug("Keep offline skipped: disabled or network not allowed")
      return
    }

    guard Audiobookshelf.shared.authentication.server?.permissions?.download == true else {
      AppLogger.download.debug("Keep offline skipped: no download permission")
      return
    }

    guard let current = PlayerManager.shared.current else {
      AppLogger.download.debug("Keep offline skipped: nothing playing")
      return
    }

    guard current.downloadState == .downloaded else {
      AppLogger.download.debug("Keep offline skipped: current item not downloaded")
      return
    }

    isReconciling = true

    Task {
      if let podcastID = current.podcastID {
        await reconcilePodcast(id: podcastID, episodeID: current.id)
      } else {
        await reconcileSeries(bookID: current.id)
      }

      isReconciling = false
    }
  }

  private func reconcileSeries(bookID: String) async {
    let count = preferences.keepOfflineCount

    guard let localBooks = try? LocalBook.fetchAll() else { return }

    guard let currentBook = localBooks.first(where: { $0.bookID == bookID }),
      let seriesID = currentBook.series.first?.id
    else {
      AppLogger.download.debug("Keep offline skipped: current book has no series")
      return
    }

    let unlistened = localBooks.count { book in
      book.bookID != bookID
        && book.series.contains { $0.id == seriesID }
        && MediaProgress.progress(for: book.bookID) < 1.0
    }

    guard unlistened < count else {
      AppLogger.download.debug("Keep offline satisfied for series \(seriesID)")
      return
    }

    AppLogger.download.info("Keep offline reconciling series \(seriesID)")

    do {
      let filter = "series.\(Data(seriesID.utf8).base64EncodedString())"
      var books: [Book] = []
      var page = 0

      while true {
        let response = try await Audiobookshelf.shared.books.fetch(
          limit: 100,
          page: page,
          filter: filter,
          libraryID: currentBook.libraryID
        )
        books.append(contentsOf: response.results)

        page += 1
        if (page * 100) >= response.total { break }
      }

      guard let index = books.firstIndex(where: { $0.id == bookID }) else {
        AppLogger.download.debug("Keep offline skipped: current book not in series \(seriesID)")
        return
      }

      let window = books[(index + 1)...]
        .filter { MediaProgress.progress(for: $0.id) < 1.0 }
        .prefix(count)

      for book in window {
        await downloadBook(book)
      }
    } catch {
      AppLogger.download.error("Keep offline reconcile failed for series \(seriesID): \(error)")
    }
  }

  private func reconcilePodcast(id: String, episodeID: String) async {
    let count = preferences.keepOfflineCount

    guard let localEpisodes = try? LocalEpisode.fetchAll() else { return }

    let unlistened = localEpisodes.count { episode in
      episode.episodeID != episodeID
        && episode.podcast?.podcastID == id
        && MediaProgress.progress(for: episode.episodeID) < 1.0
    }

    guard unlistened < count else {
      AppLogger.download.debug("Keep offline satisfied for podcast \(id)")
      return
    }

    AppLogger.download.info("Keep offline reconciling podcast \(id)")

    do {
      let podcast = try await Audiobookshelf.shared.podcasts.fetch(id: id)
      let sort = preferences.podcastEpisodeSort
      let ascending = preferences.podcastEpisodeSortAscending
      let episodes = (podcast.media.episodes ?? [])
        .sorted { sort.areInOrder($0, $1, ascending: ascending) }

      guard let index = episodes.firstIndex(where: { $0.id == episodeID }) else {
        AppLogger.download.debug("Keep offline skipped: current episode not in podcast \(id)")
        return
      }

      let window = episodes[(index + 1)...]
        .filter { MediaProgress.progress(for: $0.id) < 1.0 }
        .prefix(count)

      for episode in window {
        await downloadEpisode(episode, podcast: podcast)
      }
    } catch {
      AppLogger.download.error("Keep offline reconcile failed for podcast \(id): \(error)")
    }
  }

  private func downloadBook(_ book: Book) async {
    guard await StorageManager.shared.canDownload(additionalBytes: book.size ?? 0) else { return }

    downloadManager.startDownload(
      for: book.id,
      type: .book,
      info: .init(
        title: book.title,
        coverURL: book.coverURL(),
        duration: book.duration,
        size: book.size,
        startedAt: Date()
      )
    )
  }

  private func downloadEpisode(_ episode: PodcastEpisode, podcast: Podcast) async {
    guard await StorageManager.shared.canDownload(additionalBytes: episode.size ?? 0) else { return }

    downloadManager.startDownload(
      for: episode.id,
      type: .episode(podcastID: podcast.id, episodeID: episode.id),
      info: .init(
        title: episode.title,
        coverURL: podcast.coverURL(),
        duration: episode.duration,
        size: episode.size,
        startedAt: Date()
      )
    )
  }

  private var isNetworkAllowed: Bool {
    switch preferences.keepOfflineMode {
    case .off:
      false
    case .wifiOnly:
      NetworkMonitor.shared.interfaceType == .wifi
    case .wifiAndCellular:
      NetworkMonitor.shared.isConnected
    }
  }
}
