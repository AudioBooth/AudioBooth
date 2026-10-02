import API
import Combine
import Models
import Nuke
import SwiftUI

final class EpisodeCardModel: EpisodeCard.Model {
  private static var backgroundColors: [URL: Color] = [:]

  private var progressObservation: Task<Void, Never>?

  init(podcast: Podcast, episode: PodcastEpisode) {
    let progress = MediaProgress.progress(for: episode.id)
    let coverURL = podcast.coverURL(raw: true)
    let duration = episode.duration ?? episode.audioTrack?.duration ?? episode.audioFile?.duration

    super.init(
      id: episode.id,
      podcastID: podcast.id,
      title: episode.title,
      coverURL: coverURL,
      summary: episode.description?.htmlStripped,
      publishedAt: episode.publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
      duration: duration,
      progress: progress,
      contextMenu: PodcastEpisodeContextMenuModel(
        episodeID: episode.id,
        podcastID: podcast.id,
        podcastTitle: podcast.title,
        podcastAuthor: podcast.author,
        coverURL: coverURL,
        episodeTitle: episode.title,
        episodeDuration: duration,
        episodeSize: episode.audioTrack?.metadata?.size ?? episode.size,
        isCompleted: progress >= 1.0,
        progress: progress,
        apiEpisode: episode
      )
    )

    observeMediaProgress()
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
    setupBackgroundColor()
  }

  isolated deinit {
    progressObservation?.cancel()
  }

  override func onPlayTapped() {
    contextMenu.onPlayTapped()
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
      let averageColor = image.averageColor
    else { return }

    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
    let color = Color(hue: hue, saturation: saturation, brightness: min(brightness, 0.4))
    Self.backgroundColors[coverURL] = color
    backgroundColor = color
  }
}
