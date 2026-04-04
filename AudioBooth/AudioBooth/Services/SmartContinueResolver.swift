import API
import Foundation
import Logging
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
    currentPodcastID: String?,
    origin: PlayerManager.Origin
  ) async -> ResolvedItem? {
    switch origin {
    case .podcast(let podcastID):
      return await resolveNextEpisode(
        currentEpisodeID: currentItemID,
        podcastID: podcastID
      )

    case .series(let seriesID, let libraryID):
      return await resolveNextBook(
        currentBookID: currentItemID,
        seriesID: seriesID,
        libraryID: libraryID
      )

    case .playlist(let playlistID):
      return await resolveFromPlaylist(
        currentItemID: currentItemID,
        currentPodcastID: currentPodcastID,
        playlistID: playlistID
      )

    case .collection(let collectionID):
      return await resolveFromCollection(
        currentItemID: currentItemID,
        collectionID: collectionID
      )
    }
  }

  private func resolveNextEpisode(
    currentEpisodeID: String,
    podcastID: String
  ) async -> ResolvedItem? {
    do {
      let podcast = try await audiobookshelf.podcasts.fetch(id: podcastID)
      return nextEpisode(
        after: currentEpisodeID,
        in: podcast
      )
    } catch {
      AppLogger.player.warning("Smart continue: failed to fetch podcast, trying offline")
      return resolveNextEpisodeOffline(
        currentEpisodeID: currentEpisodeID,
        podcastID: podcastID
      )
    }
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

  private func resolveNextEpisodeOffline(
    currentEpisodeID: String,
    podcastID: String
  ) -> ResolvedItem? {
    guard let podcast = try? LocalPodcast.fetch(podcastID: podcastID) else { return nil }

    let episodes = podcast.episodes
    guard let currentIndex = episodes.firstIndex(where: { $0.episodeID == currentEpisodeID }) else {
      return nil
    }

    let nextIndex = episodes.index(after: currentIndex)
    guard nextIndex < episodes.endIndex else { return nil }

    let next = episodes[nextIndex]
    return ResolvedItem(
      bookID: next.episodeID,
      title: next.title,
      details: podcast.title,
      coverURL: podcast.coverURL(),
      podcastID: podcast.podcastID
    )
  }

  private func resolveNextBook(
    currentBookID: String,
    seriesID: String,
    libraryID: String
  ) async -> ResolvedItem? {
    let base64SeriesID = Data(seriesID.utf8).base64EncodedString()
    let filter = "series.\(base64SeriesID)"

    do {
      let page = try await audiobookshelf.books.fetch(
        limit: 100,
        sortBy: .title,
        filter: filter,
        libraryID: libraryID
      )
      return nextBook(after: currentBookID, in: page.results)
    } catch {
      AppLogger.player.warning("Smart continue: failed to fetch series, trying offline")
      return resolveNextBookOffline(currentBookID: currentBookID, seriesID: seriesID)
    }
  }

  private func nextBook(after currentBookID: String, in books: [Book]) -> ResolvedItem? {
    guard let currentIndex = books.firstIndex(where: { $0.id == currentBookID }) else {
      return nil
    }

    let nextIndex = books.index(after: currentIndex)
    guard nextIndex < books.endIndex else { return nil }

    let next = books[nextIndex]
    return ResolvedItem(
      bookID: next.id,
      title: next.title,
      details: next.authorName,
      coverURL: next.coverURL(),
      podcastID: nil
    )
  }

  private func resolveNextBookOffline(
    currentBookID: String,
    seriesID: String
  ) -> ResolvedItem? {
    guard let allBooks = try? LocalBook.fetchAll() else { return nil }

    let booksInSeries =
      allBooks
      .filter { $0.series.contains(where: { $0.id == seriesID }) }

    guard let currentIndex = booksInSeries.firstIndex(where: { $0.bookID == currentBookID }) else {
      return nil
    }

    let nextIndex = booksInSeries.index(after: currentIndex)
    guard nextIndex < booksInSeries.endIndex else { return nil }

    let next = booksInSeries[nextIndex]
    return ResolvedItem(
      bookID: next.bookID,
      title: next.title,
      details: next.authors.first?.name,
      coverURL: next.coverURL,
      podcastID: nil
    )
  }

  private func resolveFromPlaylist(
    currentItemID: String,
    currentPodcastID: String?,
    playlistID: String
  ) async -> ResolvedItem? {
    if let podcastID = currentPodcastID {
      if let next = await resolveNextEpisode(
        currentEpisodeID: currentItemID,
        podcastID: podcastID
      ) {
        return next
      }
    } else {
      if let next = await resolveNextBookInSeries(currentBookID: currentItemID) {
        return next
      }
    }

    return await resolveNextPlaylistItem(
      currentItemID: currentItemID,
      playlistID: playlistID
    )
  }

  private func resolveNextPlaylistItem(
    currentItemID: String,
    playlistID: String
  ) async -> ResolvedItem? {
    guard let playlist = try? await audiobookshelf.playlists.fetch(id: playlistID) else {
      return nil
    }

    let itemID = currentItemID
    guard
      let currentIndex = playlist.items.firstIndex(where: {
        $0.episodeID == itemID || $0.libraryItemID == itemID
      })
    else {
      return nil
    }

    let nextIndex = playlist.items.index(after: currentIndex)
    guard nextIndex < playlist.items.endIndex else { return nil }

    let next = playlist.items[nextIndex]
    return resolvedItem(from: next)
  }

  private func resolveFromCollection(
    currentItemID: String,
    collectionID: String
  ) async -> ResolvedItem? {
    if let next = await resolveNextBookInSeries(currentBookID: currentItemID) {
      return next
    }

    guard let collection = try? await audiobookshelf.collections.fetch(id: collectionID) else {
      return nil
    }

    return nextBook(after: currentItemID, in: collection.books)
  }

  private func resolveNextBookInSeries(currentBookID: String) async -> ResolvedItem? {
    guard let localBook = try? LocalBook.fetch(bookID: currentBookID),
      let series = localBook.series.first,
      let libraryID = localBook.libraryID
    else {
      return nil
    }

    return await resolveNextBook(
      currentBookID: currentBookID,
      seriesID: series.id,
      libraryID: libraryID
    )
  }

  private func resolvedItem(from playlistItem: PlaylistItem) -> ResolvedItem {
    if let episode = playlistItem.episode {
      let podcastID: String?
      if case .podcast(let podcast) = playlistItem.libraryItem {
        podcastID = podcast.id
      } else {
        podcastID = playlistItem.libraryItemID
      }
      return ResolvedItem(
        bookID: episode.id,
        title: episode.title,
        details: playlistItem.title,
        coverURL: playlistItem.coverURL,
        podcastID: podcastID
      )
    } else {
      return ResolvedItem(
        bookID: playlistItem.libraryItemID,
        title: playlistItem.title,
        details: nil,
        coverURL: playlistItem.coverURL,
        podcastID: nil
      )
    }
  }
}
