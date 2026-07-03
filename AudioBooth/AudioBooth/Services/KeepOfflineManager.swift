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
  private var needsAnotherPass = false

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
    guard Audiobookshelf.shared.authentication.isAuthenticated else { return }
    guard preferences.keepOfflineMode != .off else { return }
    guard isNetworkAllowed else { return }
    guard Audiobookshelf.shared.authentication.server?.permissions?.download == true else { return }
    guard let current = PlayerManager.shared.current else { return }

    guard !isReconciling else {
      needsAnotherPass = true
      return
    }

    isReconciling = true

    Task {
      let count = preferences.keepOfflineCount

      if let podcastID = current.podcastID {
        await reconcilePodcast(id: podcastID, count: count)
      } else {
        await reconcileSeries(bookID: current.id, count: count)
      }

      isReconciling = false

      if needsAnotherPass {
        needsAnotherPass = false
        reconcile()
      }
    }
  }

  private func reconcileSeries(bookID: String, count: Int) async {
    do {
      let book = try await Audiobookshelf.shared.books.fetch(id: bookID)
      guard let seriesID = book.series?.first?.id else { return }

      let filter = "series.\(Data(seriesID.utf8).base64EncodedString())"
      var books: [Book] = []
      var page = 0

      while true {
        let response = try await Audiobookshelf.shared.books.fetch(
          limit: 100,
          page: page,
          filter: filter,
          libraryID: book.libraryID
        )
        books.append(contentsOf: response.results)

        page += 1
        if (page * 100) >= response.total { break }
      }

      for book in books where MediaProgress.progress(for: book.id) >= 1.0 {
        removeBookDownload(book.id)
      }

      let window =
        books
        .filter { MediaProgress.progress(for: $0.id) < 1.0 }
        .prefix(count)

      for book in window {
        await downloadBook(book)
      }
    } catch {
      AppLogger.download.error("Keep offline reconcile failed for book \(bookID): \(error)")
    }
  }

  private func reconcilePodcast(id: String, count: Int) async {
    do {
      let podcast = try await Audiobookshelf.shared.podcasts.fetch(id: id)
      let sort = preferences.podcastEpisodeSort
      let ascending = preferences.podcastEpisodeSortAscending
      let episodes = (podcast.media.episodes ?? [])
        .sorted { sort.areInOrder($0, $1, ascending: ascending) }

      for episode in episodes where MediaProgress.progress(for: episode.id) >= 1.0 {
        removeEpisodeDownload(episode.id, podcastID: podcast.id)
      }

      let window =
        episodes
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
    guard downloadManager.downloadStates[book.id] != .downloaded else { return }
    guard !downloadManager.isDownloading(for: book.id) else { return }
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
    guard downloadManager.downloadStates[episode.id] != .downloaded else { return }
    guard !downloadManager.isDownloading(for: episode.id) else { return }
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

  private func removeBookDownload(_ bookID: String) {
    guard bookID != PlayerManager.shared.current?.id else { return }
    guard downloadManager.downloadStates[bookID] == .downloaded else { return }
    downloadManager.deleteDownload(for: bookID)
  }

  private func removeEpisodeDownload(_ episodeID: String, podcastID: String) {
    guard episodeID != PlayerManager.shared.current?.id else { return }
    guard downloadManager.downloadStates[episodeID] == .downloaded else { return }
    downloadManager.deleteEpisodeDownload(episodeID: episodeID, podcastID: podcastID)
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
