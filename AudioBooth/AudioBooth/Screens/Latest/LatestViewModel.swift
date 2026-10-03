import API
import Combine
import Foundation
import Logging
import Models
import UIKit

final class LatestViewModel: LatestView.Model {
  private let libraries = Audiobookshelf.shared.libraries
  private let playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()
  private var hasFetched = false

  init() {
    super.init()

    libraries.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.hasFetched = false
        self?.episodes = []
        self?.onAppear()
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self, self.hasFetched else { return }
        Task { await self.fetchEpisodes() }
      }
      .store(in: &cancellables)

    playerManager.$current
      .sink { [weak self] current in
        self?.observePlaybackState(current)
      }
      .store(in: &cancellables)
  }

  override func onAppear() {
    guard !hasFetched else { return }
    Task {
      await fetchEpisodes()
    }
  }

  override func refresh() async {
    await fetchEpisodes()
  }

  override func onPlayTapped(_ episode: Episode) {
    if let current = playerManager.current, current.id == episode.id {
      current.onTogglePlaybackTapped()
    } else {
      episode.contextMenu?.onPlayTapped()
    }
  }

  private func fetchEpisodes() async {
    guard Audiobookshelf.shared.libraries.current?.mediaType == .podcast else { return }

    if episodes.isEmpty {
      isLoading = true
    }

    defer { isLoading = false }

    do {
      let recentEpisodes = try await libraries.fetchRecentEpisodes()
      episodes = recentEpisodes.map(makeEpisode(from:))
      hasFetched = true
    } catch {
      AppLogger.viewModel.error("Failed to fetch recent episodes: \(error)")
    }
  }

  private func makeEpisode(from recent: RecentEpisode) -> Episode {
    let episodeID = recent.episode.id
    let progress = MediaProgress.progress(for: episodeID)
    let coverURL = recent.coverURL()

    let contextMenu = PodcastEpisodeContextMenuModel(
      episodeID: episodeID,
      podcastID: recent.libraryItemID,
      podcastTitle: recent.podcastTitle,
      podcastAuthor: recent.podcastAuthor,
      coverURL: coverURL,
      episodeTitle: recent.episode.title,
      episodeDuration: recent.episode.duration,
      episodeSize: recent.episode.audioTrack?.metadata?.size ?? recent.episode.size,
      isCompleted: progress >= 1.0,
      progress: progress,
      apiEpisode: recent.episode
    )
    contextMenu.onProgressChanged = { [weak self] in
      self?.refreshProgress(episodeID: episodeID)
    }

    return Episode(
      id: episodeID,
      podcastID: recent.libraryItemID,
      podcastTitle: recent.podcastTitle,
      title: recent.episode.title,
      coverURL: coverURL,
      publishedAt: recent.episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
      duration: recent.episode.duration,
      progress: progress,
      summary: recent.episode.description?.htmlStripped,
      contextMenu: contextMenu
    )
  }

  private func refreshProgress(episodeID: String) {
    guard let index = episodes.firstIndex(where: { $0.id == episodeID }) else { return }
    episodes[index].progress = MediaProgress.progress(for: episodeID)
  }

  private func observePlaybackState(_ current: BookPlayer.Model?) {
    currentEpisodeID = current?.id
    isPlaying = current?.isPlaying ?? false
    isPlayerLoading = current?.isLoading ?? false

    guard let current else { return }

    withObservationTracking {
      _ = current.isPlaying
      _ = current.isLoading
    } onChange: { [weak self, weak current] in
      Task { @MainActor [weak self, weak current] in
        guard let self, let current, current === self.playerManager.current else { return }
        self.observePlaybackState(current)
      }
    }
  }
}
