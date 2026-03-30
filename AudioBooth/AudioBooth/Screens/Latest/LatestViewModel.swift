import API
import Combine
import Foundation
import Logging
import Models
import UIKit

final class LatestViewModel: LatestView.Model {
  private let libraries = Audiobookshelf.shared.libraries
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

  private func fetchEpisodes() async {
    guard Audiobookshelf.shared.isAuthenticated else { return }

    if episodes.isEmpty {
      isLoading = true
    }

    defer { isLoading = false }

    do {
      let recentEpisodes = try await libraries.fetchRecentEpisodes()
      episodes = recentEpisodes.map { recent in
        Episode(
          id: recent.episode.id,
          podcastID: recent.libraryItemID,
          podcastTitle: recent.podcastTitle,
          title: recent.episode.title,
          coverURL: recent.coverURL(),
          publishedAt: recent.episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
          duration: recent.episode.duration,
          progress: MediaProgress.progress(for: recent.episode.id)
        )
      }
      hasFetched = true
    } catch {
      AppLogger.viewModel.error("Failed to fetch recent episodes: \(error)")
    }
  }
}
