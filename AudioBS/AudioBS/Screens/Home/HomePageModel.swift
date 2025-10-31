import API
import Models
import OSLog
import SwiftData
import SwiftUI

final class HomePageModel: HomePage.Model {
  private let downloadManager = DownloadManager.shared
  private var playerManager = PlayerManager.shared

  private var availableOfflineTask: Task<Void, Never>?

  private var availableOffline: [LocalBook] = []

  private var books: [Book] = [] {
    didSet { refreshContinueListening() }
  }

  init() {
    super.init()
    setupLocalBooksObservation()
    loadCachedContent()
  }

  override func onAppear() {
    Task {
      await fetchRemoteContent()
    }
  }

  override func refresh() async {
    await fetchRemoteContent()
  }

  override func onReset(_ shouldRefresh: Bool) {
    availableOffline = []
    books = []
    others = []
    continueListening = nil
    offline = nil
    isLoading = false

    if shouldRefresh {
      onAppear()
    }
  }
}

extension HomePageModel {
  private func setupLocalBooksObservation() {
    availableOfflineTask = Task { [weak self] in
      for await books in LocalBook.observeAll() {
        guard !Task.isCancelled else { break }
        self?.availableOffline = books
        self?.refreshContinueListening()
      }
    }
  }

  private func refreshContinueListening() {
    let existingModels: [String: ContinueListeningCardModel]
    if case .continueListening(let items) = continueListening?.items {
      existingModels = Dictionary(
        uniqueKeysWithValues: items.compactMap { item in
          guard let cardModel = item as? ContinueListeningCardModel else { return nil }
          return (cardModel.id, cardModel)
        }
      )
    } else {
      existingModels = [:]
    }

    var models: [ContinueListeningCardModel] = []

    for book in self.books {
      let model: ContinueListeningCardModel

      if let existingModel = existingModels[book.id] {
        model = existingModel
      } else {
        model = ContinueListeningCardModel(
          book: book,
          onRemoved: { [weak self] in
            guard let self else { return }
            self.books = self.books.filter({ $0.id != book.id })
          }
        )
      }

      models.append(model)
    }

    let sorted = models.sorted(by: >)

    if !sorted.isEmpty {
      self.continueListening = Section(
        title: "Continue Listening", items: .continueListening(sorted))
    } else {
      self.continueListening = nil
    }

    var offlineBooks = [(model: BookCard.Model, book: LocalBook)]()

    for book in availableOffline {
      if !downloadManager.isDownloading(for: book.bookID),
        !book.isDownloaded,
        playerManager.current?.id != book.bookID
      {
        try? book.delete()
      } else if book.isDownloaded {
        let model = BookCardModel(book)
        offlineBooks.append((model, book))
      }
    }

    if !offlineBooks.isEmpty {
      let currentBookID = playerManager.current?.id
      let currentBook = availableOffline.first { $0.bookID == currentBookID }
      let currentSeriesID = currentBook?.series.first?.id
      let currentSequence = currentBook?.series.first?.sequence

      offlineBooks.sort { pair1, pair2 in
        let series1 = pair1.book.series.first
        let series2 = pair2.book.series.first

        guard let s1 = series1 else { return false }
        guard let s2 = series2 else { return true }

        let isBook1InCurrentSeries = s1.id == currentSeriesID
        let isBook2InCurrentSeries = s2.id == currentSeriesID

        if isBook1InCurrentSeries && !isBook2InCurrentSeries {
          return true
        }
        if !isBook1InCurrentSeries && isBook2InCurrentSeries {
          return false
        }

        if isBook1InCurrentSeries && isBook2InCurrentSeries, let currentSeq = currentSequence {
          let seq1Value = Double(s1.sequence) ?? 0
          let seq2Value = Double(s2.sequence) ?? 0
          let currentSeqValue = Double(currentSeq) ?? 0

          let isBook1CurrentOrAfter = seq1Value >= currentSeqValue
          let isBook2CurrentOrAfter = seq2Value >= currentSeqValue

          if isBook1CurrentOrAfter && isBook2CurrentOrAfter {
            return seq1Value < seq2Value
          }

          if !isBook1CurrentOrAfter && !isBook2CurrentOrAfter {
            return seq1Value > seq2Value
          }

          return isBook1CurrentOrAfter
        }

        if s1.name != s2.name {
          return s1.name < s2.name
        }

        let seq1Value = Double(s1.sequence) ?? 0
        let seq2Value = Double(s2.sequence) ?? 0
        return seq1Value < seq2Value
      }

      let offline = offlineBooks.map { $0.model }
      self.offline = Section(title: "Available Offline", items: .books(offline))
    } else {
      self.offline = nil
    }
  }

  private func processSections(_ personalized: [Personalized.Section]) {
    var sections = [Section]()

    for section in personalized {
      switch section.entities {
      case .books(let items):
        if section.id == "continue-listening" {
          books = items
          continue
        } else {
          let books = items.map({ BookCardModel($0, sortBy: .title) })
          sections.append(.init(title: section.label, items: .books(books)))
        }

      case .series(let items):
        let series = items.map { SeriesCardModel(series: $0) }
        sections.append(.init(title: section.label, items: .series(series)))

      case .authors(let items):
        let authors = items.map { AuthorCardModel(author: $0) }
        sections.append(.init(title: section.label, items: .authors(authors)))

      case .unknown:
        continue
      }
    }

    self.others = sections
  }

}

extension HomePageModel {
  private func loadCachedContent() {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return
    }

    processSections(personalized.sections)
  }

  private func fetchRemoteContent() async {
    if others.isEmpty {
      isLoading = true
    }

    do {
      try await MediaProgress.syncFromAPI()

      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      processSections(personalized.sections)
    } catch {
      AppLogger.viewModel.error("Failed to fetch personalized content: \(error)")
    }

    isLoading = false
  }
}
