import API
import Foundation
import Logging
import Models
import SwiftUI

final class OfflineListViewModel: OfflineListView.Model {
  private var audiobookshelf: Audiobookshelf { .shared }
  private var downloadManager: DownloadManager { .shared }

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
    sortOrder = UserPreferences.shared.offlineSortOrder
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
    guard
      sortOrder == .manual,
      searchText.trimmingCharacters(in: .whitespaces).isEmpty,
      let lowerBound = source.min(),
      let upperBound = source.max(),
      lowerBound >= 0,
      upperBound < filteredBooks.count,
      destination <= filteredBooks.count
    else { return }

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
    let idsToDelete = indexSet.compactMap { index -> String? in
      guard index < items.count else { return nil }
      return items[index].id
    }

    deleteItems(Set(idsToDelete))
  }

  override func onSearchChanged() {
    updateDisplayedItems()
  }

  override func onGroupSeriesToggled() {
    groupingEnabled.toggle()
    isGroupedBySeries = groupingEnabled
    UserPreferences.shared.groupSeriesInOffline = groupingEnabled
    updateDisplayedItems()
  }

  override func onSortOrderTapped(_ order: OfflineListView.Model.SortOrder) {
    guard order != sortOrder else { return }

    sortOrder = order
    UserPreferences.shared.offlineSortOrder = order

    allBooks = sortedBooks(allBooks)
    filteredBooks = allBooks
    allEpisodes = sortedEpisodes(allEpisodes)
    filteredEpisodes = allEpisodes

    updateDisplayedItems()
  }
}

extension OfflineListViewModel {
  private func setupBooksObservation() {
    booksObservation = Task { [weak self] in
      for await books in LocalBook.observeAll() {
        guard !Task.isCancelled, let self else { break }

        if !self.isReordering {
          let downloaded = books.filter { $0.isDownloaded || $0.mediaType.contains(.ebook) }
          self.allBooks = self.sortedBooks(downloaded)
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

        self.allEpisodes = self.sortedEpisodes(episodes.filter { $0.isDownloaded })
        self.filteredEpisodes = self.allEpisodes
        self.updateDisplayedItems()
        self.isLoading = false
      }
    }
  }
}

extension OfflineListViewModel {
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

    var slots: [BookSlot] = []
    var seriesBooks: [String: [LocalBook]] = [:]

    for book in localBooks {
      guard let firstSeries = book.series.first else {
        slots.append(.book(book))
        continue
      }

      if seriesBooks[firstSeries.id] == nil {
        seriesBooks[firstSeries.id] = []
        slots.append(.series(id: firstSeries.id, name: firstSeries.name))
      }

      seriesBooks[firstSeries.id]?.append(book)
    }

    return slots.map { slot -> OfflineListItem in
      switch slot {
      case .book(let book):
        return .book(BookCardModel(book))

      case .series(let id, let name):
        let books = orderedWithinGroup(seriesBooks[id] ?? [])

        return .series(
          SeriesGroup(
            id: id,
            name: name,
            books: books.map { BookCardModel($0, options: .showSequence) },
            coverURL: books.first?.coverURL
          )
        )
      }
    }
  }

  private func buildEpisodeItems(from localEpisodes: [LocalEpisode]) -> [OfflineListItem] {
    guard !localEpisodes.isEmpty else { return [] }

    guard groupingEnabled else {
      return localEpisodes.map { .episode(makeEpisodeCardModel($0)) }
    }

    var podcastIDs: [String] = []
    var podcastEpisodes: [String: [LocalEpisode]] = [:]

    for episode in localEpisodes {
      let key = episode.podcast?.podcastID ?? episode.episodeID

      if podcastEpisodes[key] == nil {
        podcastEpisodes[key] = []
        podcastIDs.append(key)
      }

      podcastEpisodes[key]?.append(episode)
    }

    return podcastIDs.compactMap { key -> OfflineListItem? in
      guard let episodes = podcastEpisodes[key], let first = episodes.first else { return nil }

      return .podcast(
        PodcastGroup(
          id: key,
          name: first.podcast?.title ?? first.title,
          episodes: orderedWithinGroup(episodes).map { makeEpisodeCardModel($0) },
          coverURL: first.podcast?.coverURL ?? first.coverURL
        )
      )
    }
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
}

extension OfflineListViewModel {
  private enum BookSlot {
    case book(LocalBook)
    case series(id: String, name: String)
  }

  private func sortedBooks(_ books: [LocalBook]) -> [LocalBook] {
    switch sortOrder {
    case .manual: books.sorted()
    case .newest: sortedByDownloadDate(books, ascending: false)
    case .oldest: sortedByDownloadDate(books, ascending: true)
    }
  }

  private func sortedEpisodes(_ episodes: [LocalEpisode]) -> [LocalEpisode] {
    switch sortOrder {
    case .manual: episodes
    case .newest: sortedByDownloadDate(episodes, ascending: false)
    case .oldest: sortedByDownloadDate(episodes, ascending: true)
    }
  }

  private func sortedByDownloadDate<Item: DownloadDateSortable>(
    _ items: [Item],
    ascending: Bool
  ) -> [Item] {
    items.sorted { first, second in
      if first.downloadDate != second.downloadDate {
        return ascending
          ? first.downloadDate < second.downloadDate
          : first.downloadDate > second.downloadDate
      }

      let order = first.title.localizedCaseInsensitiveCompare(second.title)
      guard order == .orderedSame else { return order == .orderedAscending }

      return first.downloadSortID < second.downloadSortID
    }
  }

  private func orderedWithinGroup(_ books: [LocalBook]) -> [LocalBook] {
    guard sortOrder == .manual else { return books }

    return books.sorted { book1, book2 in
      let sequence1 = Double(book1.series.first?.sequence ?? "0") ?? 0
      let sequence2 = Double(book2.series.first?.sequence ?? "0") ?? 0
      return sequence1 < sequence2
    }
  }

  private func orderedWithinGroup(_ episodes: [LocalEpisode]) -> [LocalEpisode] {
    guard sortOrder == .manual else { return episodes }

    return episodes.sorted {
      ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
    }
  }
}

protocol DownloadDateSortable {
  var title: String { get }
  var downloadSortID: String { get }
  var downloadDate: Date { get }
}

extension LocalBook: DownloadDateSortable {
  var downloadSortID: String { bookID }
  var downloadDate: Date { downloadedAt ?? createdAt }
}

extension LocalEpisode: DownloadDateSortable {
  var downloadSortID: String { episodeID }
  var downloadDate: Date { downloadedAt ?? createdAt }
}

extension OfflineListViewModel {
  private func saveDisplayOrder() async {
    let bookIDs = filteredBooks.map(\.bookID)

    do {
      try LocalBook.updateDisplayOrders(bookIDs)
    } catch {
      AppLogger.viewModel.error("Failed to save display order: \(error)")
    }
  }
}

extension OfflineListViewModel {
  private func deleteSelected() async {
    isPerformingBatchAction = true
    deleteItems(selectedIDs)
    selectedIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }

  private func deleteItems(_ ids: Set<String>) {
    let books = allBooks.filter { ids.contains($0.bookID) }
    let episodes = allEpisodes.filter { ids.contains($0.episodeID) }

    allBooks.removeAll { ids.contains($0.bookID) }
    filteredBooks.removeAll { ids.contains($0.bookID) }
    allEpisodes.removeAll { ids.contains($0.episodeID) }
    filteredEpisodes.removeAll { ids.contains($0.episodeID) }
    updateDisplayedItems()

    for book in books {
      book.removeDownload()
    }

    for episode in episodes {
      guard let podcastID = episode.podcast?.podcastID else { continue }
      downloadManager.deleteEpisodeDownload(episodeID: episode.episodeID, podcastID: podcastID)
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
          AppLogger.viewModel.error("Failed to mark book \(id) as finished: \(error)")
        }
      } else if let episode = allEpisodes.first(where: { $0.episodeID == id }) {
        do {
          let podcastID = episode.podcast?.podcastID ?? ""
          let episodeProgressID = "\(podcastID)/\(episode.episodeID)"
          try MediaProgress.markAsFinished(for: episode.episodeID)
          try await audiobookshelf.progress.markAsFinished(bookID: episodeProgressID)
        } catch {
          AppLogger.viewModel.error("Failed to mark episode \(id) as finished: \(error)")
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
          AppLogger.viewModel.error("Failed to reset progress for book \(id): \(error)")
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
            let apiProgress = try await audiobookshelf.progress.fetch(
              bookID: episodeProgressID
            )
            progressID = apiProgress.id
          }

          try await audiobookshelf.progress.reset(progressID: progressID)

          if let progress {
            try progress.delete()
          }
        } catch {
          AppLogger.viewModel.error("Failed to reset progress for episode \(id): \(error)")
        }
      }
    }

    selectedIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }
}
