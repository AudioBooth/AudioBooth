import API
import Combine
import Models
import Nuke
import SwiftUI

final class EpisodeCardModel: EpisodeCard.Model {
  private static var backgroundColors: [URL: Color] = [:]

  private let playerManager = PlayerManager.shared
  private var progressObservation: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  init(podcast: Podcast, episode: PodcastEpisode) {
    let progress = MediaProgress.progress(for: episode.id)
    let coverURL = podcast.coverURL(raw: true)

    super.init(
      id: episode.id,
      podcastID: podcast.id,
      title: episode.title,
      coverURL: coverURL,
      summary: episode.description?.htmlStripped,
      publishedAt: episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
      duration: episode.duration,
      progress: progress,
      contextMenu: PodcastEpisodeContextMenuModel(
        episodeID: episode.id,
        podcastID: podcast.id,
        podcastTitle: podcast.title,
        podcastAuthor: podcast.author,
        coverURL: coverURL,
        episodeTitle: episode.title,
        episodeDuration: episode.duration,
        episodeSize: episode.audioTrack?.metadata?.size ?? episode.size,
        isCompleted: progress >= 1.0,
        progress: progress,
        apiEpisode: episode
      )
    )

    observeMediaProgress()
    observePlayer()
    setupBackgroundColor()
  }

  init?(localEpisode episode: LocalEpisode) {
    guard let podcast = episode.podcast else { return nil }

    let progress = MediaProgress.progress(for: episode.episodeID)

    super.init(
      id: episode.episodeID,
      podcastID: podcast.podcastID,
      title: episode.title,
      coverURL: episode.coverURL(),
      summary: episode.episodeDescription?.htmlStripped,
      publishedAt: episode.publishedAt,
      duration: episode.duration,
      progress: progress,
      contextMenu: PodcastEpisodeContextMenuModel(
        episodeID: episode.episodeID,
        podcastID: podcast.podcastID,
        podcastTitle: podcast.title,
        podcastAuthor: podcast.author,
        coverURL: episode.coverURL,
        episodeTitle: episode.title,
        episodeDuration: episode.duration,
        episodeSize: nil,
        isCompleted: progress >= 1.0,
        progress: progress
      )
    )

    observeMediaProgress()
    observePlayer()
    setupBackgroundColor()
  }

  isolated deinit {
    progressObservation?.cancel()
  }

  override func onPlayTapped() {
    if let current = playerManager.current, current.id == id {
      current.onTogglePlaybackTapped()
    } else {
      contextMenu.onPlayTapped()
    }
  }

  private func observePlayer() {
    playerManager.$current
      .sink { [weak self] current in
        self?.observePlaybackState(current)
      }
      .store(in: &cancellables)
  }

  private func observePlaybackState(_ current: BookPlayer.Model?) {
    guard let current, current.id == id else {
      if isPlaying { isPlaying = false }
      return
    }

    isPlaying = current.isPlaying

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self, weak current] in
      Task { @MainActor [weak self, weak current] in
        guard let self, let current, current === self.playerManager.current else { return }
        self.observePlaybackState(current)
      }
    }
  }

  private func observeMediaProgress() {
    let episodeID = id
    progressObservation = Task { [weak self] in
      for await _ in MediaProgress.observe(where: \.bookID, equals: episodeID) {
        self?.progress = MediaProgress.progress(for: episodeID)
      }
    }
  }

  private func setupBackgroundColor() {
    guard let coverURL else { return }

    if let color = Self.backgroundColors[coverURL] {
      backgroundColor = color
      return
    }

    Task { [weak self] in
      await self?.loadBackgroundColor(coverURL)
    }
  }

  private func loadBackgroundColor(_ coverURL: URL) async {
    let request = ImageRequest(url: coverURL, processors: [.resize(width: 40)])
    guard let image = try? await ImagePipeline.shared.image(for: request),
      let palette = image.coverPalette
    else { return }

    let color = Color(palette.background)
    Self.backgroundColors[coverURL] = color
    backgroundColor = color
  }
}
