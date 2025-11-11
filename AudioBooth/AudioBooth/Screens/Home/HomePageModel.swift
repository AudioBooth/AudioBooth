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
    didSet {
      refreshDynamicSections()

      Task { @MainActor in
        if playerManager.current == nil, let book = books.first {
          playerManager.current = BookPlayerModel(book)
        }
      }
    }
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
    books = []
    others = []
    continueListening = nil
    offline = nil
    isLoading = false

    refreshDynamicSections()

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
        self?.refreshDynamicSections()
      }
    }
  }

  private func refreshDynamicSections() {
    refreshContinueListeningSection()
    refreshOfflineSection()
  }

  private func refreshContinueListeningSection() {
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
  }

  private func refreshOfflineSection() {
    var downloadedBooks: [LocalBook] = []

    for book in availableOffline {
      if !downloadManager.isDownloading(for: book.bookID),
        !book.isDownloaded,
        playerManager.current?.id != book.bookID
      {
        try? book.delete()
      } else if book.isDownloaded {
        downloadedBooks.append(book)
      }
    }

    guard !downloadedBooks.isEmpty else {
      self.offline = nil
      return
    }

    let sortedBooks = downloadedBooks.sorted(current: playerManager.current?.id)

    let models = sortedBooks.map { BookCardModel($0) }
    self.offline = Section(title: "Available Offline", items: .books(models))
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
    refreshDynamicSections()
  }

  private func fetchRemoteContent() async {
    guard Audiobookshelf.shared.isAuthenticated else { return }

    if others.isEmpty {
      isLoading = true
    }

    do {
      let userData = try await Audiobookshelf.shared.authentication.fetchMe()
      try? MediaProgress.syncFromAPI(userData: userData)
      try? Bookmark.syncFromAPI(userData: userData)

      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      processSections(personalized.sections)
      refreshDynamicSections()
    } catch {
      AppLogger.viewModel.error("Failed to fetch personalized content: \(error)")
    }

    isLoading = false
  }
}
