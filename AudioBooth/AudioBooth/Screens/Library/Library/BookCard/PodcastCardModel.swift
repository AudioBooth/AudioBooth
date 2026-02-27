import API
import Foundation
import Models

final class PodcastCardModel: BookCard.Model {
  private let podcast: Podcast
  private var progressObservation: Task<Void, Never>?

  init(_ podcast: Podcast, sortBy: SortBy?) {
    self.podcast = podcast

    let id = podcast.recentEpisode?.id ?? podcast.id

    let title = podcast.recentEpisode?.title ?? podcast.title
    let author = podcast.author

    let details: String?
    let time: Date.FormatStyle.TimeStyle
    if UserPreferences.shared.libraryDisplayMode == .row {
      time = .shortened
    } else {
      time = .omitted
    }

    switch sortBy {
    case .title, .author, .random, .numEpisodes:
      details = "\(podcast.numEpisodes) Episodes"
    case .addedAt:
      details = "Added \(podcast.addedAt.formatted(date: .numeric, time: time))"
    case .size:
      details = podcast.size.map {
        "Size \($0.formatted(.byteCount(style: .file)))"
      }
    case .birthtime, .modified:
      details = "\(podcast.numEpisodes) Episodes"
    default:
      details = nil
    }

    let cover = Cover.Model(
      url: podcast.coverURL(),
      title: title,
      author: author,
      progress: MediaProgress.progress(for: id)
    )

    let progress = MediaProgress.progress(for: id)
    let episodeContextMenu = PodcastEpisodeContextMenuModel(
      episodeID: id,
      podcastID: podcast.id,
      podcastTitle: podcast.title,
      podcastAuthor: podcast.author,
      coverURL: podcast.coverURL(raw: true),
      episodeTitle: title,
      episodeDuration: podcast.recentEpisode?.duration,
      episodeSize: podcast.recentEpisode?.audioTrack?.metadata?.size ?? podcast.recentEpisode?.size,
      isCompleted: progress >= 1.0,
      progress: progress,
      apiEpisode: podcast.recentEpisode
    )

    super.init(
      id: id,
      podcastID: podcast.id,
      title: title,
      details: details,
      cover: cover,
      author: author,
      episodeContextMenu: episodeContextMenu
    )

    if sortBy == nil {
      observeMediaProgress()
    }
  }

  private func observeMediaProgress() {
    let episodeID = id
    progressObservation = Task { [weak self] in
      for await _ in MediaProgress.observe(where: \.bookID, equals: episodeID) {
        self?.cover.progress = MediaProgress.progress(for: episodeID)
      }
    }
  }
}
