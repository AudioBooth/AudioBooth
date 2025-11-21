import API
import Logging
import Models
import SwiftData
import SwiftUI

final class HomePageModel: HomePage.Model {
  private let downloadManager = DownloadManager.shared
  private let playerManager = PlayerManager.shared
  private let preferences = UserPreferences.shared

  private var availableOfflineTask: Task<Void, Never>?

  private var availableOffline: [LocalBook] = []
  private var continueListeningBooks: [Book] = []
  private var personalizedSections: [Personalized.Section] = []

  init() {
    super.init()
    loadCachedContent()
  }

  override func onAppear() {
    if Audiobookshelf.shared.isAuthenticated && availableOfflineTask == nil {
      setupLocalBooksObservation()
    }

    Task {
      await fetchRemoteContent()
    }
  }

  override func refresh() async {
    if Audiobookshelf.shared.libraries.current != nil {
      _ = try? await Audiobookshelf.shared.libraries.fetchFilterData()
    }
    await fetchRemoteContent()
  }

  override func onReset(_ shouldRefresh: Bool) {
    playerManager.clearCurrent()

    availableOffline = []
    continueListeningBooks = []
    personalizedSections = []
    sections = []
    isLoading = false

    availableOfflineTask?.cancel()
    availableOfflineTask = nil

    if shouldRefresh {
      onAppear()
    }
  }

  override func onPreferencesChanged() {
    rebuildSections()
  }
}

extension HomePageModel {
  private func setupLocalBooksObservation() {
    availableOfflineTask = Task { [weak self] in
      for await books in LocalBook.observeAll() {
        guard !Task.isCancelled else { break }
        self?.availableOffline = books
        self?.rebuildSections()
      }
    }
  }

  private func processSections(_ personalized: [Personalized.Section]) {
    personalizedSections = personalized

    for section in personalized {
      if section.id == "continue-listening" {
        if case .books(let items) = section.entities {
          continueListeningBooks = items
          WatchConnectivityManager.shared.syncContinueListening(books: items)
        }
        break
      }
    }

    rebuildSections()
  }

  private func rebuildSections() {
    guard Audiobookshelf.shared.isAuthenticated else {
      self.sections = []
      return
    }

    let enabledSections = Set(preferences.homeSections.map(\.rawValue))

    var sectionsByID: [String: Section] = [:]

    for section in personalizedSections {
      guard enabledSections.contains(section.id) else { continue }

      switch section.entities {
      case .books(let items):
        if section.id == "continue-listening" {
          continue
        } else {
          let books = items.map({ BookCardModel($0, sortBy: .title) })
          sectionsByID[section.id] = .init(
            id: section.id, title: section.label, items: .books(books))
        }

      case .series(let items):
        let series = items.map { SeriesCardModel(series: $0) }
        sectionsByID[section.id] = .init(
          id: section.id, title: section.label, items: .series(series))

      case .authors(let items):
        let authors = items.map { AuthorCardModel(author: $0) }
        sectionsByID[section.id] = .init(
          id: section.id, title: section.label, items: .authors(authors))

      case .unknown:
        continue
      }
    }

    let continueListeningSection = buildContinueListeningSection()
    let offlineSection = buildOfflineSection()

    var orderedSections: [Section] = []

    for sectionID in preferences.homeSections {
      switch sectionID {
      case .listeningStats:
        orderedSections.append(Section(id: "listening-stats", title: "", items: .stats))

      case .continueListening:
        if let section = continueListeningSection {
          orderedSections.append(section)
        }

      case .availableOffline:
        if let section = offlineSection {
          orderedSections.append(section)
        }

      default:
        if let section = sectionsByID[sectionID.rawValue] {
          orderedSections.append(section)
        }
      }
    }

    self.sections = orderedSections
  }

  private func buildContinueListeningSection() -> Section? {
    let existingModels: [String: ContinueListeningCardModel]
    if let existingSection = sections.first(where: { $0.id == "continue-listening" }),
      case .continueListening(let items) = existingSection.items
    {
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

    for book in continueListeningBooks {
      let model: ContinueListeningCardModel

      if let existingModel = existingModels[book.id] {
        model = existingModel
      } else {
        model = ContinueListeningCardModel(
          book: book,
          onRemoved: { [weak self] in
            guard let self else { return }
            self.continueListeningBooks = self.continueListeningBooks.filter({ $0.id != book.id })
            self.rebuildSections()
          }
        )
      }

      models.append(model)
    }

    let sorted = models.sorted(by: >)

    guard !sorted.isEmpty else { return nil }

    return Section(
      id: "continue-listening",
      title: "Continue Listening",
      items: .continueListening(sorted)
    )
  }

  private func buildOfflineSection() -> Section? {
    var downloadedBooks: [LocalBook] = []

    for book in availableOffline {
      if !downloadManager.isDownloading(for: book.bookID),
        !book.isDownloaded,
        playerManager.current?.id != book.bookID
      {
        Task {
          try? book.delete()
        }
      } else if book.isDownloaded {
        downloadedBooks.append(book)
      }
    }

    guard !downloadedBooks.isEmpty else { return nil }

    let sortedBooks = downloadedBooks.sorted()
    let models = sortedBooks.map { BookCardModel($0) }

    return Section(
      id: "available-offline",
      title: "Available Offline",
      items: .offline(models)
    )
  }
}

extension HomePageModel {
  private func loadCachedContent() {
    guard Audiobookshelf.shared.isAuthenticated else { return }

    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return
    }

    processSections(personalized.sections)
  }

  private func fetchRemoteContent() async {
    guard Audiobookshelf.shared.isAuthenticated else { return }

    if sections.isEmpty {
      isLoading = true
    }

    do {
      let userData = try await Audiobookshelf.shared.authentication.fetchMe()
      try? MediaProgress.syncFromAPI(
        userData: userData,
        currentPlayingBookID: PlayerManager.shared.current?.id
      )
      try? Bookmark.syncFromAPI(userData: userData)

      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      processSections(personalized.sections)
    } catch {
      AppLogger.viewModel.error("Failed to fetch personalized content: \(error)")
    }

    isLoading = false
  }
}
