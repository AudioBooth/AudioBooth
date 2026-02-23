import API
import Foundation
import Logging
import Models

final class PodcastEpisodeContextMenuModel: PodcastEpisodeContextMenu.Model {
  private let episodeID: String
  private let podcastID: String
  private let podcastTitle: String
  private let podcastAuthor: String?
  private let coverURL: URL?
  private let episodeTitle: String
  private let episodeDuration: Double?
  private let episodeSize: Int64?
  private let apiEpisode: PodcastEpisode?

  private let playerManager = PlayerManager.shared
  private let downloadManager = DownloadManager.shared

  init(
    episodeID: String,
    podcastID: String,
    podcastTitle: String,
    podcastAuthor: String?,
    coverURL: URL?,
    episodeTitle: String,
    episodeDuration: Double?,
    episodeSize: Int64?,
    isCompleted: Bool,
    progress: Double,
    apiEpisode: PodcastEpisode? = nil
  ) {
    self.episodeID = episodeID
    self.podcastID = podcastID
    self.podcastTitle = podcastTitle
    self.podcastAuthor = podcastAuthor
    self.coverURL = coverURL
    self.episodeTitle = episodeTitle
    self.episodeDuration = episodeDuration
    self.episodeSize = episodeSize
    self.apiEpisode = apiEpisode

    let downloadState = DownloadManager.shared.downloadStates[episodeID] ?? .notDownloaded

    var actions: PodcastEpisodeContextMenu.Model.Actions = [.addToPlaylist]
    if progress > 0 { actions.insert(.resetProgress) }
    if !isCompleted { actions.insert(.markAsFinished) }

    let isCurrentEpisode = PlayerManager.shared.current?.id == episodeID
    if !isCurrentEpisode {
      let isInQueue = PlayerManager.shared.queue.contains { $0.bookID == episodeID }
      actions.insert(isInQueue ? .removeFromQueue : .addToQueue)
    }

    super.init(downloadState: downloadState, actions: actions)
  }

  override func onAppear() {
    downloadState = downloadManager.downloadStates[episodeID] ?? .notDownloaded

    let progress = MediaProgress.progress(for: episodeID)
    let isCompleted = progress >= 1.0

    var updatedActions: PodcastEpisodeContextMenu.Model.Actions = [.addToPlaylist]
    if progress > 0 { updatedActions.insert(.resetProgress) }
    if !isCompleted { updatedActions.insert(.markAsFinished) }

    let isCurrentEpisode = playerManager.current?.id == episodeID
    if !isCurrentEpisode {
      let isInQueue = playerManager.queue.contains { $0.bookID == episodeID }
      updatedActions.insert(isInQueue ? .removeFromQueue : .addToQueue)
    }

    actions = updatedActions
  }

  override func onPlayTapped() {
    if let localEpisode = try? LocalEpisode.fetch(episodeID: episodeID) {
      playerManager.setCurrent(localEpisode)
    } else if let apiEpisode {
      playerManager.setCurrent(
        episode: apiEpisode,
        podcastID: podcastID,
        podcastTitle: podcastTitle,
        podcastAuthor: podcastAuthor,
        coverURL: coverURL
      )
    }
    playerManager.play()
  }

  override func onAddToQueueTapped() {
    let durationText: String? = episodeDuration.map {
      Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
    playerManager.addToQueue(
      QueueItem(
        bookID: episodeID,
        title: episodeTitle,
        details: durationText,
        coverURL: coverURL,
        podcastID: podcastID
      )
    )
    actions.remove(.addToQueue)
    actions.insert(.removeFromQueue)
  }

  override func onRemoveFromQueueTapped() {
    playerManager.removeFromQueue(bookID: episodeID)
    actions.remove(.removeFromQueue)
    actions.insert(.addToQueue)
  }

  override func onDownloadTapped() {
    let size = episodeSize ?? 0
    var details = ""
    if let duration = episodeDuration, duration > 0 {
      details = Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
    if size > 0 {
      if !details.isEmpty { details += " • " }
      details += size.formatted(.byteCount(style: .file))
    }

    Task {
      let canDownload = await StorageManager.shared.canDownload(additionalBytes: size)
      guard canDownload else {
        Toast(error: "Storage limit reached").show()
        return
      }
      downloadManager.startDownload(
        for: episodeID,
        type: .episode(podcastID: podcastID, episodeID: episodeID),
        info: .init(
          title: episodeTitle,
          details: details.isEmpty ? nil : details,
          coverURL: coverURL,
          startedAt: Date()
        )
      )
    }
  }

  override func onCancelDownloadTapped() {
    downloadManager.cancelDownload(for: episodeID)
  }

  override func onRemoveDownloadTapped() {
    downloadManager.deleteEpisodeDownload(episodeID: episodeID, podcastID: podcastID)
  }

  override func onMarkAsFinishedTapped() {
    let episodeProgressID = "\(podcastID)/\(episodeID)"
    Task {
      do {
        try MediaProgress.markAsFinished(for: episodeID)
        try await Audiobookshelf.shared.libraries.markAsFinished(bookID: episodeProgressID)
        actions.remove(.markAsFinished)
        actions.insert(.resetProgress)
      } catch {
        AppLogger.viewModel.error("Failed to mark episode as finished: \(error)")
      }
    }
  }

  override func onAddToPlaylistTapped() {
    showingPlaylistSheet = true
  }

  override func onResetProgressTapped() {
    let episodeProgressID = "\(podcastID)/\(episodeID)"
    Task {
      do {
        let progress = try MediaProgress.fetch(bookID: episodeID)
        let progressID: String
        if let progress, let id = progress.id {
          progressID = id
        } else {
          let apiProgress = try await Audiobookshelf.shared.libraries.fetchMediaProgress(
            bookID: episodeProgressID
          )
          progressID = apiProgress.id
        }
        try await Audiobookshelf.shared.libraries.resetBookProgress(progressID: progressID)
        if let progress {
          try progress.delete()
        }
        actions.remove(.resetProgress)
        actions.insert(.markAsFinished)
      } catch {
        AppLogger.viewModel.error("Failed to reset episode progress: \(error)")
      }
    }
  }
}
