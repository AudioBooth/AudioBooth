import API
import Foundation

final class PodcastCardModel: BookCard.Model {
  private let podcast: Podcast

  init(_ podcast: Podcast, sortBy: SortBy?) {
    self.podcast = podcast

    let title = podcast.title
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
      author: author
    )

    super.init(
      id: podcast.id,
      title: title,
      details: details,
      cover: cover,
      author: author,
      isPodcast: true
    )
  }
}
