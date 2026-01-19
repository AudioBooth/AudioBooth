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
  private var booksObservation: Task<Void, Never>?
  private var isReordering = false
  private var groupingEnabled: Bool = false

  init() {
    super.init()
    groupingEnabled = UserPreferences.shared.groupSeriesInOffline
    isGroupedBySeries = groupingEnabled
  }

  override func onAppear() {
    if allBooks.isEmpty {
      isLoading = true
    }

    setupBooksObservation()
  }

  override func onEditModeTapped() {
    if editMode == .active {
      selectedBookIDs.removeAll()
      editMode = .inactive
    } else {
      editMode = .active
    }
  }

  override func onSelectBook(id: String) {
    if selectedBookIDs.contains(id) {
      selectedBookIDs.remove(id)
    } else {
      selectedBookIDs.insert(id)
    }
  }

  override func onDeleteSelected() {
    guard !selectedBookIDs.isEmpty else { return }

    Task {
      await deleteSelectedBooks()
    }
  }

  override func onMarkFinishedSelected() {
    guard !selectedBookIDs.isEmpty else { return }

    Task {
      await markSelectedBooksAsFinished()
    }
  }

  override func onResetProgressSelected() {
    guard !selectedBookIDs.isEmpty else { return }

    Task {
      await resetSelectedBooksProgress()
    }
  }

  override func onSelectAllTapped() {
    if selectedBookIDs.count == books.count {
      selectedBookIDs.removeAll()
    } else {
      selectedBookIDs = Set(books.map(\.id))
    }
  }

  override func onReorder(from source: IndexSet, to destination: Int) {
    isReordering = true

    var reorderedBooks = books
    reorderedBooks.move(fromOffsets: source, toOffset: destination)
    books = reorderedBooks

    var reorderedLocalBooks = filteredBooks
    reorderedLocalBooks.move(fromOffsets: source, toOffset: destination)
    filteredBooks = reorderedLocalBooks

    items = buildDisplayItems(from: filteredBooks)

    Task { @MainActor in
      await saveDisplayOrder()
    }
  }

  override func onDelete(at indexSet: IndexSet) {
    let booksToDelete = indexSet.map { books[$0] }
    let bookIDsToDelete = Set(booksToDelete.map(\.id))

    Task {
      await deleteBooks(bookIDsToDelete)
    }
  }

  override func onGroupSeriesToggled() {
    groupingEnabled.toggle()
    isGroupedBySeries = groupingEnabled
    UserPreferences.shared.groupSeriesInOffline = groupingEnabled
    updateDisplayedBooks()
  }

  private func setupBooksObservation() {
    booksObservation = Task { [weak self] in
      for await books in LocalBook.observeAll() {
        guard !Task.isCancelled, let self else { break }

        Task { @MainActor in
          if !self.isReordering {
            self.allBooks = books.filter { $0.isDownloaded }.sorted()
            self.filteredBooks = self.allBooks
            self.updateDisplayedBooks()
          }

          self.isReordering = false
          self.isLoading = false
        }
      }
    }
  }

  private func buildDisplayItems(from localBooks: [LocalBook]) -> [OfflineListItem] {
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
        SeriesBookItem(
          book: BookCardModel(localBook),
          sequence: localBook.series.first?.sequence ?? ""
        )
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

  private func updateDisplayedBooks() {
    let searchTerm = searchText.lowercased().trimmingCharacters(in: .whitespaces)

    let booksToDisplay: [LocalBook]
    if searchTerm.isEmpty {
      booksToDisplay = filteredBooks
    } else {
      booksToDisplay = filteredBooks.filter { book in
        book.title.lowercased().contains(searchTerm)
          || book.authorNames.lowercased().contains(searchTerm)
      }
    }

    items = buildDisplayItems(from: booksToDisplay)
    books = booksToDisplay.map { BookCardModel($0) }
  }

  private func saveDisplayOrder() async {
    let bookIDs = filteredBooks.map(\.bookID)

    do {
      try LocalBook.updateDisplayOrders(bookIDs)
    } catch {
      print("Failed to save display order: \(error)")
    }
  }

  private func deleteSelectedBooks() async {
    isPerformingBatchAction = true
    await deleteBooks(selectedBookIDs)
    selectedBookIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }

  private func deleteBooks(_ bookIDs: Set<String>) async {
    for bookID in bookIDs {
      guard let book = allBooks.first(where: { $0.bookID == bookID }) else { continue }
      book.removeDownload()
    }
  }

  private func markSelectedBooksAsFinished() async {
    isPerformingBatchAction = true
    let selectedIDs = Array(selectedBookIDs)

    for bookID in selectedIDs {
      guard let book = allBooks.first(where: { $0.bookID == bookID }) else { continue }

      do {
        try await book.markAsFinished()
      } catch {
        print("Failed to mark book \(bookID) as finished: \(error)")
      }
    }

    selectedBookIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }

  private func resetSelectedBooksProgress() async {
    isPerformingBatchAction = true
    let selectedIDs = Array(selectedBookIDs)

    for bookID in selectedIDs {
      guard let book = allBooks.first(where: { $0.bookID == bookID }) else { continue }

      do {
        try await book.resetProgress()
      } catch {
        print("Failed to reset progress for book \(bookID): \(error)")
      }
    }

    selectedBookIDs.removeAll()
    editMode = .inactive
    isPerformingBatchAction = false
  }
}
