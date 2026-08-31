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
  private let preferences = UserPreferences.shared

  func resolve(
    currentItemID: String,
    currentPodcastID: String?
  ) async -> ResolvedItem? {
    if let currentPodcastID {
      guard preferences.continueNextPodcastEpisode else { return nil }

      guard let podcast = try? await audiobookshelf.podcasts.fetch(id: currentPodcastID) else {
        return resolveNextOfflineEpisode(currentEpisodeID: currentItemID)
      }
      return nextEpisode(after: currentItemID, in: podcast)
    } else {
      if preferences.continueNextInSeries,
        let next = await resolveNextBookInSeries(currentBookID: currentItemID)
      {
        return next
      }

      guard preferences.continueNextDownloadedBook else { return nil }
      return resolveNextOfflineBook(currentBookID: currentItemID)
    }
  }
}

extension SmartContinueResolver {
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
    guard let next = remaining.first(where: { MediaProgress.progress(for: $0.id) < 1.0 }) else {
      return nil
    }

    return ResolvedItem(
      bookID: next.id,
      title: next.title,
      details: podcast.title,
      coverURL: podcast.coverURL(),
      podcastID: podcast.id
    )
  }

  private func sortedEpisodes(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
    let sort = preferences.podcastEpisodeSort
    let ascending = preferences.podcastEpisodeSortAscending
    return episodes.sorted { sort.areInOrder($0, $1, ascending: ascending) }
  }

  private func resolveNextOfflineEpisode(currentEpisodeID: String) -> ResolvedItem? {
    let episodes = ((try? LocalEpisode.fetchAll()) ?? []).filter { $0.isDownloaded }
    guard let currentIndex = episodes.firstIndex(where: { $0.episodeID == currentEpisodeID }) else {
      return nil
    }

    let remaining = episodes[episodes.index(after: currentIndex)...]
    guard let next = remaining.first(where: { MediaProgress.progress(for: $0.episodeID) < 1.0 })
    else {
      return nil
    }

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

    let remaining = page.results[page.results.index(after: currentIndex)...]
    guard let next = remaining.first(where: { MediaProgress.progress(for: $0.id) < 1.0 }) else {
      return nil
    }

    return ResolvedItem(
      bookID: next.id,
      title: next.title,
      details: next.authorName,
      coverURL: next.coverURL(),
      podcastID: nil
    )
  }

  private func resolveNextOfflineBook(currentBookID: String) -> ResolvedItem? {
    let books = (try? LocalBook.fetchAll())?.filter { $0.isDownloaded }.sorted() ?? []
    let isPlayable: (LocalBook) -> Bool = { book in
      book.bookID != currentBookID && MediaProgress.progress(for: book.bookID) < 1.0
    }

    let following: ArraySlice<LocalBook> =
      if let currentIndex = books.firstIndex(where: { $0.bookID == currentBookID }) {
        books[books.index(after: currentIndex)...]
      } else {
        []
      }

    guard let next = following.first(where: isPlayable) ?? books.first(where: isPlayable) else {
      return nil
    }

    return ResolvedItem(
      bookID: next.bookID,
      title: next.title,
      details: next.authors.first?.name,
      coverURL: next.coverURL,
      podcastID: nil
    )
  }
}
