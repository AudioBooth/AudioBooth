import API
import Foundation
import Logging
import Models

final class PodcastAutoQueueManager {
  static let shared = PodcastAutoQueueManager()

  private static let refreshInterval: TimeInterval = 3600

  private let preferences = UserPreferences.shared
  private let playerManager = PlayerManager.shared
  private let downloadManager = DownloadManager.shared
  private var libraries: LibrariesService { Audiobookshelf.shared.libraries }
  private var lastRefresh: Date?
  private var isRefreshing = false

  private init() {}

  private var hasEnabledPodcasts: Bool {
    !preferences.podcastAutoQueueSettings.settings.isEmpty
  }

  func refresh() {
    guard Audiobookshelf.shared.authentication.isAuthenticated else { return }
    guard hasEnabledPodcasts else { return }
    guard !isRefreshing else { return }

    if let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval {
      return
    }

    let podcastLibraries = libraries.libraries.filter { $0.mediaType == .podcast }
    guard !podcastLibraries.isEmpty else { return }

    isRefreshing = true

    Task {
      defer { isRefreshing = false }

      var didSucceed = false
      for library in podcastLibraries {
        do {
          let recentEpisodes = try await libraries.fetchRecentEpisodes(libraryID: library.id)
          process(recentEpisodes: recentEpisodes)
          didSucceed = true
        } catch {
          AppLogger.player.error("Auto-queue refresh failed for library \(library.id): \(error)")
        }
      }

      if didSucceed {
        lastRefresh = Date()
      }
    }
  }

  private func process(recentEpisodes: [RecentEpisode]) {
    guard hasEnabledPodcasts else { return }

    let grouped = Dictionary(grouping: recentEpisodes) { $0.libraryItemID }

    for (podcastID, episodes) in grouped {
      guard let setting = preferences.podcastAutoQueueSettings.settings[podcastID] else { continue }
      processPodcast(podcastID: podcastID, setting: setting, episodes: episodes)
    }

    for (podcastID, setting) in preferences.podcastAutoQueueSettings.settings where grouped[podcastID] == nil {
      let cutoff = setting.limit.timeWindow.map { nowMilliseconds - Int64($0 * 1000) }
      enforceLimit(setting.limit, podcastID: podcastID, cutoff: cutoff)
    }
  }

  private func processPodcast(
    podcastID: String,
    setting: PodcastAutoQueueSettings,
    episodes: [RecentEpisode]
  ) {
    let baseline = setting.baselinePublishedAt ?? nowMilliseconds
    let cutoff = setting.limit.timeWindow.map { nowMilliseconds - Int64($0 * 1000) }

    let newEpisodes =
      episodes
      .filter { ($0.episode.publishedAt ?? .min) > baseline }
      .sorted { ($0.episode.publishedAt ?? .min) < ($1.episode.publishedAt ?? .min) }

    var toEnqueue = newEpisodes.filter {
      MediaProgress.progress(for: $0.episode.id) < 1.0
    }

    if let cutoff {
      toEnqueue = toEnqueue.filter { ($0.episode.publishedAt ?? .min) >= cutoff }
    }

    if setting.position == .top {
      for recent in toEnqueue.reversed() {
        playerManager.addToQueue(queueItem(for: recent, podcastID: podcastID), position: .top)
      }
    } else {
      for recent in toEnqueue {
        playerManager.addToQueue(queueItem(for: recent, podcastID: podcastID), position: .bottom)
      }
    }

    enforceLimit(setting.limit, podcastID: podcastID, cutoff: cutoff)

    if !toEnqueue.isEmpty {
      AppLogger.player.info("Auto-queued \(toEnqueue.count) new episode(s) for podcast \(podcastID)")

      if preferences.autoDownloadQueuedEpisodes {
        download(toEnqueue, podcastID: podcastID)
      }
    }

    if let newestSeen = newEpisodes.compactMap({ $0.episode.publishedAt }).max(), newestSeen > baseline {
      var updated = setting
      updated.baselinePublishedAt = newestSeen
      preferences.setPodcastAutoQueueSetting(updated, for: podcastID)
    }
  }

  private func enforceLimit(_ limit: PodcastAutoQueueLimit, podcastID: String, cutoff: Int64?) {
    let items = playerManager.queue.compactMap { item -> (item: QueueItem, publishedAt: Int64)? in
      guard item.podcastID == podcastID, let publishedAt = item.publishedAt else { return nil }
      return (item, Int64(publishedAt.timeIntervalSince1970 * 1000))
    }

    let toRemove: [QueueItem]
    if let cutoff {
      toRemove = items.filter { $0.publishedAt < cutoff }.map(\.item)
    } else if let maxCount = limit.maxCount, items.count > maxCount {
      toRemove =
        items
        .sorted { $0.publishedAt > $1.publishedAt }
        .dropFirst(maxCount)
        .map(\.item)
    } else {
      return
    }

    for item in toRemove {
      playerManager.removeFromQueue(bookID: item.bookID)
      cleanUpDownload(episodeID: item.bookID, podcastID: podcastID)
    }

    if !toRemove.isEmpty {
      AppLogger.player.info("Removed \(toRemove.count) episode(s) over limit for podcast \(podcastID)")
    }
  }

  private func cleanUpDownload(episodeID: String, podcastID: String) {
    guard preferences.autoDownloadQueuedEpisodes else { return }

    switch downloadManager.downloadStates[episodeID] {
    case .downloading:
      downloadManager.cancelDownload(for: episodeID)
    case .downloaded:
      downloadManager.deleteEpisodeDownload(episodeID: episodeID, podcastID: podcastID)
    default:
      break
    }
  }

  private func download(_ episodes: [RecentEpisode], podcastID: String) {
    guard Audiobookshelf.shared.authentication.server?.permissions?.download == true else { return }

    for recent in episodes {
      let episodeID = recent.episode.id
      let state = downloadManager.downloadStates[episodeID] ?? .notDownloaded
      guard state == .notDownloaded else { continue }

      downloadManager.startDownload(
        recent.episode,
        podcastID: podcastID,
        coverURL: recent.coverURL()
      )
    }
  }

  private func queueItem(for recent: RecentEpisode, podcastID: String) -> QueueItem {
    QueueItem(
      bookID: recent.episode.id,
      title: recent.episode.title,
      details: durationText(for: recent.episode.duration),
      coverURL: recent.coverURL(),
      podcastID: podcastID,
      publishedAt: recent.episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    )
  }

  private var nowMilliseconds: Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private func durationText(for duration: Double?) -> String? {
    guard let duration, duration > 0 else { return nil }
    return Duration.seconds(duration).formatted(
      .units(allowed: [.hours, .minutes], width: .narrow)
    )
  }
}
