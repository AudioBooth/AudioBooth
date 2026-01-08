import API
import Combine
import Logging
import Models
import SwiftData
import SwiftUI
import WidgetKit

final class HomePageModel: HomePage.Model {
  private let downloadManager = DownloadManager.shared
  private let playerManager = PlayerManager.shared
  private let preferences = UserPreferences.shared

  private var availableOfflineTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  private var availableOffline: [LocalBook] = []
  private var continueListeningBooks: [Book] = []
  private var personalizedSections: [Personalized.Section] = []

  init() {
    super.init()
    loadCachedContent()

    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        Task {
          await self?.fetchRemoteContent()
        }
      }
      .store(in: &cancellables)
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
            id: section.id,
            title: section.label,
            items: .books(books)
          )
        }

      case .series(let items):
        let series = items.map { SeriesCardModel(series: $0) }
        sectionsByID[section.id] = .init(
          id: section.id,
          title: section.label,
          items: .series(series)
        )

      case .authors(let items):
        let authors = items.map { AuthorCardModel(author: $0) }
        sectionsByID[section.id] = .init(
          id: section.id,
          title: section.label,
          items: .authors(authors)
        )

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
        if let continueListeningSection {
          orderedSections.append(continueListeningSection)
        }

      case .availableOffline:
        if let offlineSection {
          orderedSections.append(offlineSection)
        }

      default:
        if let section = sectionsByID[sectionID.rawValue] {
          orderedSections.append(section)
        }
      }
    }

    self.sections = orderedSections

    WatchConnectivityManager.shared.syncContinueListening(books: continueListeningBooks)
    saveRecentBooksToWidget()
  }

  private func buildContinueListeningSection() -> Section? {
    let existingModels: [String: ContinueListeningBookCardModel]
    if let existingSection = sections.first(where: { $0.id == "continue-listening" }),
      case .continueListening(let items) = existingSection.items
    {
      existingModels = Dictionary(
        uniqueKeysWithValues: items.compactMap { item in
          guard let cardModel = item as? ContinueListeningBookCardModel else { return nil }
          return (cardModel.id, cardModel)
        }
      )
    } else {
      existingModels = [:]
    }

    let booksToDisplay = continueListeningBooks.filter { book in
      MediaProgress.progress(for: book.id) < 1.0
    }

    var models: [ContinueListeningBookCardModel] = []

    if let currentPlayerID = playerManager.current?.id,
      !booksToDisplay.contains(where: { $0.id == currentPlayerID }),
      let currentLocalBook = try? LocalBook.fetch(bookID: currentPlayerID)
    {
      if let existingModel = existingModels[currentPlayerID] {
        models.append(existingModel)
      } else {
        let model = ContinueListeningBookCardModel(
          localBook: currentLocalBook,
          onRemoved: { [weak self] in
            guard let self else { return }
            self.continueListeningBooks = self.continueListeningBooks.filter({ $0.id != currentPlayerID })
            self.rebuildSections()
          }
        )
        models.append(model)
      }
    }

    for book in booksToDisplay {
      let model: ContinueListeningBookCardModel

      if let existingModel = existingModels[book.id] {
        model = existingModel
      } else {
        model = ContinueListeningBookCardModel(
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

    let sorted = models.sorted(by: <)

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
      let data = try await Audiobookshelf.shared.authentication.authorize()
      try? MediaProgress.syncFromAPI(
        userData: data.user,
        currentPlayingBookID: PlayerManager.shared.current?.id
      )
      try? Bookmark.syncFromAPI(userData: data.user)

      let version = data.serverSettings.version
      if version.compare("2.22.0", options: .numeric) == .orderedAscending {
        error =
          "Some features may be limited on server version \(version). For the best experience, please update your server."
      }

      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      processSections(personalized.sections)
    } catch {
      AppLogger.viewModel.error("Failed to fetch personalized content: \(error)")
    }

    isLoading = false
  }
}

extension HomePageModel {
  private func saveRecentBooksToWidget() {
    struct BookEntry: Codable {
      let bookID: String
      let title: String
      let author: String
      let coverURL: URL?
    }

    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    do {
      let allProgress = try MediaProgress.fetchAll()
      let sortedProgress =
        allProgress
        .sorted { $0.lastUpdate > $1.lastUpdate }

      let offlineBooksByID = Dictionary(
        uniqueKeysWithValues: availableOffline.map { ($0.bookID, $0) }
      )
      let continueListeningByID = Dictionary(
        uniqueKeysWithValues: continueListeningBooks.map { ($0.id, $0) }
      )

      var books: [BookEntry] = []

      for progress in sortedProgress {
        guard books.count < 5 else { break }

        if let localBook = offlineBooksByID[progress.bookID] {
          let book = BookEntry(
            bookID: localBook.bookID,
            title: localBook.title,
            author: localBook.authorNames,
            coverURL: localBook.coverURL
          )
          books.append(book)
        } else if let remoteBook = continueListeningByID[progress.bookID] {
          let book = BookEntry(
            bookID: remoteBook.id,
            title: remoteBook.title,
            author: remoteBook.authorName ?? "",
            coverURL: remoteBook.coverURL()
          )
          books.append(book)
        }
      }

      let data = try JSONEncoder().encode(books)
      sharedDefaults?.set(data, forKey: "recentBooks")
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
    }
  }
}
