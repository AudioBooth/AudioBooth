import API
import Foundation
import Models

final class PodcastCardModel: BookCard.Model {
  private let podcast: Podcast

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

    super.init(
      id: id,
      podcastID: podcast.id,
      title: title,
      details: details,
      cover: cover,
      author: author
    )
  }
}
