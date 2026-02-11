import API
import Foundation
import Models
import SwiftUI

final class OfflineListViewModel: OfflineListView.Model {
  private var audiobookshelf: Audiobookshelf { .shared }
  private var downloadManager: DownloadManager { .shared }
  private var playerManager: PlayerManager { .shared }

  private var allBooks: [LocalBook] = []
  private var filteredBooks: [LocalBook] = []
  private var allEpisodes: [LocalEpisode] = []
  private var filteredEpisodes: [LocalEpisode] = []
  private var booksObservation: Task<Void, Never>?
  private var episodesObservation: Task<Void, Never>?
  private var isReordering = false
  private var groupingEnabled: Bool = false

  init() {
    super.init()
    groupingEnabled = UserPreferences.shared.groupSeriesInOffline
    isGroupedBySeries = groupingEnabled
  }

  override func onAppear() {
    if allBooks.isEmpty && allEpisodes.isEmpty {
      isLoading = true
    }

    setupBooksObservation()
    setupEpisodesObservation()
  }

  override func onEditModeTapped() {
    withAnimation {
      if editMode == .active {
        selectedIDs.removeAll()
        editMode = .inactive
      } else {
        editMode = .active
      }
    }
  }

  override func onSelectItem(id: String) {
    if selectedIDs.contains(id) {
      selectedIDs.remove(id)
    } else {
      selectedIDs.insert(id)
    }
  }

  override func onDeleteSelected() {
    guard !selectedIDs.isEmpty else { return }

    Task {
      await deleteSelected()
    }
  }

  override func onMarkFinishedSelected() {
    guard !selectedIDs.isEmpty else { return }

    Task {
      await markSelectedAsFinished()
    }
  }

  override func onResetProgressSelected() {
    guard !selectedIDs.isEmpty else { return }

    Task {
      await resetSelectedProgress()
    }
  }

  override func onSelectAllTapped() {
    if selectedIDs.count == selectableCount {
      selectedIDs.removeAll()
    } else {
      let bookIDs = filteredBooks.map(\.bookID)
      let episodeIDs = filteredEpisodes.map(\.episodeID)
      selectedIDs = Set(bookIDs + episodeIDs)
    }
  }

  override func onReorder(from source: IndexSet, to destination: Int) {
    isReordering = true

    var reorderedBooks = filteredBooks
    reorderedBooks.move(fromOffsets: source, toOffset: destination)
    filteredBooks = reorderedBooks

    updateDisplayedItems()

    Task {
      await saveDisplayOrder()
    }
  }

  override func onDelete(at indexSet: IndexSet) {
    let flatItems = buildFlatItems()
    let idsToDelete = indexSet.compactMap { index -> String? in
      guard index < flatItems.count else { return nil }
      return flatItems[index].id
    }

    Task {
      await deleteItems(Set(idsToDelete))
    }
  }

  override func onGroupSeriesToggled() {
    groupingEnabled.toggle()
    isGroupedBySeries = groupingEnabled
    UserPreferences.shared.groupSeriesInOffline = groupingEnabled
    updateDisplayedItems()
  }

  // MARK: - Observations

  private func setupBooksObservation() {
    booksObservation = Task { [weak self] in
      for await books in LocalBook.observeAll() {
        guard !Task.isCancelled, let self else { break }

        if !self.isReordering {
          self.allBooks = books.filter { $0.isDownloaded }.sorted()
          self.filteredBooks = self.allBooks
          self.updateDisplayedItems()
        }

        self.isReordering = false
        self.isLoading = false
      }
    }
  }

  private func setupEpisodesObservation() {
    episodesObservation = Task { [weak self] in
      for await episodes in LocalEpisode.observeAll() {
        guard !Task.isCancelled, let self else { break }

        self.allEpisodes = episodes.filter { $0.isDownloaded }
        self.filteredEpisodes = self.allEpisodes
        self.updateDisplayedItems()
        self.isLoading = false
      }
    }
  }

  // MARK: - Display

  private func updateDisplayedItems() {
    let searchTerm = searchText.lowercased().trimmingCharacters(in: .whitespaces)

    let booksToDisplay: [LocalBook]
    let episodesToDisplay: [LocalEpisode]

    if searchTerm.isEmpty {
      booksToDisplay = filteredBooks
      episodesToDisplay = filteredEpisodes
    } else {
      booksToDisplay = filteredBooks.filter { book in
        book.title.lowercased().contains(searchTerm)
          || book.authorNames.lowercased().contains(searchTerm)
      }
      episodesToDisplay = filteredEpisodes.filter { episode in
        episode.title.lowercased().contains(searchTerm)
          || (episode.podcast?.title.lowercased().contains(searchTerm) ?? false)
          || (episode.podcast?.author?.lowercased().contains(searchTerm) ?? false)
      }
    }

    items = buildDisplayItems(books: booksToDisplay, episodes: episodesToDisplay)
    selectableCount = booksToDisplay.count + episodesToDisplay.count
  }

  private func buildDisplayItems(
    books: [LocalBook],
    episodes: [LocalEpisode]
  ) -> [OfflineListItem] {
    var displayItems = buildBookItems(from: books)
    displayItems += buildEpisodeItems(from: episodes)
    return displayItems
  }

  private func buildBookItems(from localBooks: [LocalBook]) -> [OfflineListItem] {
    guard groupingEnabled else {
      return localBooks.map { .book(BookCardModel($0)) }
    }

    var seriesGroups: [String: (seriesID: String, seriesName: String, books: [LocalBook])] = [:]
    var booksWithoutSeries: [LocalBook] = []

    for book in localBooks {
      if let firstSeries = book.series.first {
        let key = firstSeries.id
        if seriesGroups[key] == nil {
          seriesGroups[key] = (firstSeries.id, firstSeries.name, [])
        }
        seriesGroups[key]?.books.append(book)
      } else {
        booksWithoutSeries.append(book)
      }
    }

    var displayItems: [OfflineListItem] = []

    let sortedGroups = seriesGroups.sorted { $0.value.seriesName < $1.value.seriesName }

    for (_, groupData) in sortedGroups {
      let sortedBooks = groupData.books.sorted { book1, book2 in
        let seq1 = Double(book1.series.first?.sequence ?? "0") ?? 0
        let seq2 = Double(book2.series.first?.sequence ?? "0") ?? 0
        return seq1 < seq2
      }

      let seriesBooks = sortedBooks.map { localBook in
        BookCardModel(localBook, options: .showSequence)
      }

      let coverURL = sortedBooks.first?.coverURL

      let group = SeriesGroup(
        id: groupData.seriesID,
        name: groupData.seriesName,
        books: seriesBooks,
        coverURL: coverURL
      )

      displayItems.append(.series(group))
    }

    for book in booksWithoutSeries {
      displayItems.append(.book(BookCardModel(book)))
    }

    return displayItems
  }

  private func buildEpisodeItems(from localEpisodes: [LocalEpisode]) -> [OfflineListItem] {
    guard !localEpisodes.isEmpty else { return [] }

    guard groupingEnabled else {
      return localEpisodes.map { .episode(makeEpisodeCardModel($0)) }
    }

    var podcastGroups: [String: (podcastID: String, podcastTitle: String, coverURL: URL?, episodes: [LocalEpisode])] =
      [:]

    for episode in localEpisodes {
      let key = episode.podcast?.podcastID ?? episode.episodeID
      if podcastGroups[key] == nil {
        podcastGroups[key] = (
          key,
          episode.podcast?.title ?? episode.title,
          episode.podcast?.coverURL ?? episode.coverURL,
          []
        )
      }
      podcastGroups[key]?.episodes.append(episode)
    }

    var displayItems: [OfflineListItem] = []

    let sortedGroups = podcastGroups.sorted { $0.value.podcastTitle < $1.value.podcastTitle }

    for (_, groupData) in sortedGroups {
      let sortedEpisodes = groupData.episodes.sorted {
        ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
      }

      let episodeModels = sortedEpisodes.map { makeEpisodeCardModel($0) }

      let group = PodcastGroup(
        id: groupData.podcastID,
        name: groupData.podcastTitle,
        episodes: episodeModels,
        coverURL: groupData.coverURL
      )

      displayItems.append(.podcast(group))
    }

    return displayItems
  }

  private func makeEpisodeCardModel(_ episode: LocalEpisode) -> BookCard.Model {
    let durationText = Duration.seconds(episode.duration).formatted(
      .units(allowed: [.hours, .minutes], width: .narrow)
    )

    return BookCard.Model(
      id: episode.episodeID,
      podcastID: episode.podcast?.podcastID,
      title: episode.title,
      details: durationText,
      cover: Cover.Model(
        url: episode.coverURL,
        progress: MediaProgress.progress(for: episode.episodeID)
      ),
      author: episode.podcast?.title
    )
  }

  private func buildFlatItems() -> [OfflineListItem] {
    let bookItems: [OfflineListItem] = filteredBooks.map { .book(BookCardModel($0)) }
    let episodeItems: [OfflineListItem] = filteredEpisodes.map { .episode(makeEpisodeCardModel($0)) }
    return bookItems + episodeItems
  }

  // MARK: - Display Order

  private func saveDisplayOrder() async {
    let bookIDs = filteredBooks.map(\.bookID)

    do {
      try LocalBook.updateDisplayOrders(bookIDs)
    } catch {
      print("Failed to save display order: \(error)")
    }
  }

  // MARK: - Batch Actions

  private func deleteSelected() async {
    isPerformingBatchAction = true
    await deleteItems(selectedIDs)
    selectedIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }

  private func deleteItems(_ ids: Set<String>) async {
    for id in ids {
      if let book = allBooks.first(where: { $0.bookID == id }) {
        book.removeDownload()
      } else if let episode = allEpisodes.first(where: { $0.episodeID == id }),
        let podcastID = episode.podcast?.podcastID
      {
        downloadManager.deleteEpisodeDownload(episodeID: episode.episodeID, podcastID: podcastID)
      }
    }
  }

  private func markSelectedAsFinished() async {
    isPerformingBatchAction = true
    let ids = Array(selectedIDs)

    for id in ids {
      if let book = allBooks.first(where: { $0.bookID == id }) {
        do {
          try await book.markAsFinished()
        } catch {
          print("Failed to mark book \(id) as finished: \(error)")
        }
      } else if let episode = allEpisodes.first(where: { $0.episodeID == id }) {
        do {
          let podcastID = episode.podcast?.podcastID ?? ""
          let episodeProgressID = "\(podcastID)/\(episode.episodeID)"
          try MediaProgress.markAsFinished(for: episode.episodeID)
          try await audiobookshelf.libraries.markAsFinished(bookID: episodeProgressID)
        } catch {
          print("Failed to mark episode \(id) as finished: \(error)")
        }
      }
    }

    selectedIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }

  private func resetSelectedProgress() async {
    isPerformingBatchAction = true
    let ids = Array(selectedIDs)

    for id in ids {
      if let book = allBooks.first(where: { $0.bookID == id }) {
        do {
          try await book.resetProgress()
        } catch {
          print("Failed to reset progress for book \(id): \(error)")
        }
      } else if let episode = allEpisodes.first(where: { $0.episodeID == id }) {
        do {
          let podcastID = episode.podcast?.podcastID ?? ""
          let episodeProgressID = "\(podcastID)/\(episode.episodeID)"
          let progress = try MediaProgress.fetch(bookID: episode.episodeID)
          let progressID: String

          if let progress, let progressIDValue = progress.id {
            progressID = progressIDValue
          } else {
            let apiProgress = try await audiobookshelf.libraries.fetchMediaProgress(
              bookID: episodeProgressID
            )
            progressID = apiProgress.id
          }

          try await audiobookshelf.libraries.resetBookProgress(progressID: progressID)

          if let progress {
            try progress.delete()
          }
        } catch {
          print("Failed to reset progress for episode \(id): \(error)")
        }
      }
    }

    selectedIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }
}
