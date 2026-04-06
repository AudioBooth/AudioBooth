import API
import Foundation
import Models

struct SmartContinueResolver {
  struct ResolvedItem {
    let bookID: String
    let title: String
    let details: String?
    let coverURL: URL?
    let podcastID: String?
  }

  private let audiobookshelf = Audiobookshelf.shared

  func resolve(
    currentItemID: String,
    currentPodcastID: String?
  ) async -> ResolvedItem? {
    if let currentPodcastID {
      if let next = await resolveNextEpisode(currentEpisodeID: currentItemID, podcastID: currentPodcastID) {
        return next
      }
      return resolveNextOfflineEpisode(currentEpisodeID: currentItemID)
    } else {
      if let next = await resolveNextBookInSeries(currentBookID: currentItemID) {
        return next
      }
      return resolveNextOfflineBook(currentBookID: currentItemID)
    }
  }
}

extension SmartContinueResolver {
  private func resolveNextEpisode(
    currentEpisodeID: String,
    podcastID: String
  ) async -> ResolvedItem? {
    guard let podcast = try? await audiobookshelf.podcasts.fetch(id: podcastID) else {
      return nil
    }
    return nextEpisode(after: currentEpisodeID, in: podcast)
  }

  private func nextEpisode(
    after currentEpisodeID: String,
    in podcast: Podcast
  ) -> ResolvedItem? {
    guard let episodes = podcast.media.episodes else { return nil }

    let sorted = sortedEpisodes(episodes)
    guard let currentIndex = sorted.firstIndex(where: { $0.id == currentEpisodeID }) else {
      return nil
    }

    let remaining = sorted.suffix(from: sorted.index(after: currentIndex))
    let next =
      remaining.first(where: { MediaProgress.progress(for: $0.id) < 1.0 })
      ?? sorted.first(where: { $0.id != currentEpisodeID && MediaProgress.progress(for: $0.id) < 1.0 })
    guard let next else { return nil }

    return ResolvedItem(
      bookID: next.id,
      title: next.title,
      details: podcast.title,
      coverURL: podcast.coverURL(),
      podcastID: podcast.id
    )
  }

  private func sortedEpisodes(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
    episodes.sorted { a, b in
      guard let aDate = a.publishedAt, let bDate = b.publishedAt else { return false }
      return aDate < bDate
    }
  }

  private func resolveNextOfflineEpisode(currentEpisodeID: String) -> ResolvedItem? {
    let episodes = (try? LocalEpisode.fetchAll()) ?? []
    guard let currentIndex = episodes.firstIndex(where: { $0.episodeID == currentEpisodeID }) else {
      return nil
    }

    let nextIndex = episodes.index(after: currentIndex)
    guard nextIndex < episodes.endIndex else { return nil }

    let next = episodes[nextIndex]
    return ResolvedItem(
      bookID: next.episodeID,
      title: next.title,
      details: next.podcast?.title,
      coverURL: next.coverURL,
      podcastID: next.podcast?.podcastID
    )
  }
}

extension SmartContinueResolver {
  private func resolveNextBookInSeries(currentBookID: String) async -> ResolvedItem? {
    guard
      let localBook = try? LocalBook.fetch(bookID: currentBookID),
      let series = localBook.series.first,
      let libraryID = localBook.libraryID
    else { return nil }

    let base64SeriesID = Data(series.id.utf8).base64EncodedString()
    let filter = "series.\(base64SeriesID)"

    guard
      let page = try? await audiobookshelf.books.fetch(
        limit: 100,
        filter: filter,
        libraryID: libraryID
      )
    else { return nil }

    guard let currentIndex = page.results.firstIndex(where: { $0.id == currentBookID }) else {
      return nil
    }

    let nextIndex = page.results.index(after: currentIndex)
    guard nextIndex < page.results.endIndex else { return nil }

    let next = page.results[nextIndex]
    return ResolvedItem(
      bookID: next.id,
      title: next.title,
      details: next.authorName,
      coverURL: next.coverURL(),
      podcastID: nil
    )
  }

  private func resolveNextOfflineBook(currentBookID: String) -> ResolvedItem? {
    let books = (try? LocalBook.fetchAll())?.sorted() ?? []
    guard let currentIndex = books.firstIndex(where: { $0.bookID == currentBookID }) else {
      return nil
    }

    let nextIndex = books.index(after: currentIndex)
    guard nextIndex < books.endIndex else { return nil }

    let next = books[nextIndex]
    return ResolvedItem(
      bookID: next.bookID,
      title: next.title,
      details: next.authors.first?.name,
      coverURL: next.coverURL,
      podcastID: nil
    )
  }
}
