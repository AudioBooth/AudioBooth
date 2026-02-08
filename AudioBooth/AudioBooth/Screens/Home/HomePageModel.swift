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
  private let pinnedPlaylistManager = PinnedPlaylistManager.shared

  private var cancellables = Set<AnyCancellable>()

  private var continueListeningBooks: [Book] = []
  private var personalizedSections: [Personalized.Section] = []
  private var pinnedPlaylist: Playlist?
  private var isFetchingRemoteContent = false

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

    pinnedPlaylistManager.objectWillChange
      .sink { [weak self] _ in
        Task {
          await self?.fetchPinnedPlaylist()
          self?.rebuildSections()
        }
      }
      .store(in: &cancellables)
  }

  override func onAppear() {
    Task {
      await fetchContent()
    }

    updateDownloadStates()
  }

  override func refresh() async {
    if Audiobookshelf.shared.libraries.current != nil {
      _ = try? await Audiobookshelf.shared.libraries.fetchFilterData()
    }
    await fetchContent()
  }

  override func onReset(_ shouldRefresh: Bool) {
    playerManager.clearCurrent()
    playerManager.clearQueue()

    continueListeningBooks = []
    personalizedSections = []
    pinnedPlaylist = nil
    sections = []
    isLoading = false

    if shouldRefresh {
      onAppear()
    }
  }

  override func onPreferencesChanged() {
    rebuildSections()
  }
}

extension HomePageModel {
  private func updateDownloadStates() {
    guard Audiobookshelf.shared.isAuthenticated, let books = try? LocalBook.fetchAll() else { return }

    for book in books {
      if book.isDownloaded {
        downloadManager.downloadStates[book.bookID] = .downloaded
      } else {
        downloadManager.downloadStates[book.bookID] = .notDownloaded
      }
    }
  }
}

extension HomePageModel {
  private func fetchContent() async {
    async let pinnedPlaylistFetch = fetchPinnedPlaylist
    async let remoteContentFetch = fetchRemoteContent

    _ = await [pinnedPlaylistFetch(), remoteContentFetch()]
  }

  private func fetchPinnedPlaylist() async {
    guard let playlistID = pinnedPlaylistManager.pinnedPlaylistID else {
      pinnedPlaylist = nil
      Audiobookshelf.shared.playlists.pinnedPlaylist = nil
      return
    }

    do {
      let playlist = try await Audiobookshelf.shared.playlists.fetch(id: playlistID)
      pinnedPlaylist = playlist
      Audiobookshelf.shared.playlists.pinnedPlaylist = playlist
    } catch {
      AppLogger.viewModel.error("Failed to fetch pinned playlist: \(error)")
    }
  }
}

extension HomePageModel {
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

      let title = HomeSection(rawValue: section.id)?.displayName ?? section.label

      switch section.entities {
      case .books(let items):
        if section.id == "continue-listening" {
          continue
        } else if section.id == "continue-reading" {
          let books = items.map({ BookCardModel($0, sortBy: .title) })
          sectionsByID[section.id] = .init(
            id: section.id,
            title: title,
            items: .continueBooks(books)
          )
        } else if section.id == "continue-series" {
          let books = items.map({ BookCardModel($0, sortBy: .title, options: .showSequence) })
          sectionsByID[section.id] = .init(
            id: section.id,
            title: title,
            items: .books(books)
          )
        } else {
          let books = items.map({ BookCardModel($0, sortBy: .title) })
          sectionsByID[section.id] = .init(
            id: section.id,
            title: title,
            items: .books(books)
          )
        }

      case .series(let items):
        let series = items.map { SeriesCardModel(series: $0) }
        sectionsByID[section.id] = .init(
          id: section.id,
          title: title,
          items: .series(series)
        )

      case .authors(let items):
        let authors = items.map { AuthorCardModel(author: $0) }
        sectionsByID[section.id] = .init(
          id: section.id,
          title: title,
          items: .authors(authors)
        )

      case .podcasts(let items):
        let podcasts = items.map { PodcastCardModel($0, sortBy: nil) }
        sectionsByID[section.id] = .init(
          id: section.id,
          title: title,
          items: .books(podcasts)
        )

      case .episodes(let items):
        let podcasts = items.map { PodcastCardModel($0, sortBy: nil) }
        if section.id == "continue-listening" {
          sectionsByID[section.id] = .init(
            id: section.id,
            title: title,
            items: .continueBooks(podcasts)
          )
        } else {
          sectionsByID[section.id] = .init(
            id: section.id,
            title: title,
            items: .books(podcasts)
          )
        }

      case .unknown:
        continue
      }
    }

    let continueListeningSection = buildContinueListeningSection()
    let pinnedPlaylistSection = buildPinnedPlaylistSection()

    var orderedSections: [Section] = []

    for sectionID in preferences.homeSections {
      switch sectionID {
      case .listeningStats:
        orderedSections.append(Section(id: "listening-stats", title: "", items: .stats))

      case .pinnedPlaylist:
        if let pinnedPlaylistSection {
          orderedSections.append(pinnedPlaylistSection)
        }

      case .continueListening:
        if let continueListeningSection {
          orderedSections.append(continueListeningSection)
        } else if let section = sectionsByID[sectionID.rawValue] {
          orderedSections.append(section)
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
      case .continueBooks(let items) = existingSection.items
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
      title: String(localized: "Continue Listening"),
      items: .continueBooks(sorted)
    )
  }

  private func buildPinnedPlaylistSection() -> Section? {
    guard let playlist = pinnedPlaylist else { return nil }
    guard !playlist.books.isEmpty else { return nil }

    let models = playlist.books.map { BookCardModel($0, sortBy: .title) }

    return Section(
      id: "pinned-playlist",
      title: playlist.name,
      items: .playlist(id: playlist.id, items: models)
    )
  }
}

extension HomePageModel {
  private func loadCachedContent() {
    guard Audiobookshelf.shared.isAuthenticated else { return }

    if let cachedPlaylist = Audiobookshelf.shared.playlists.pinnedPlaylist,
      cachedPlaylist.id == pinnedPlaylistManager.pinnedPlaylistID
    {
      pinnedPlaylist = cachedPlaylist
    }

    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return
    }

    processSections(personalized.sections)
  }

  private func fetchRemoteContent() async {
    guard Audiobookshelf.shared.isAuthenticated, !isFetchingRemoteContent else { return }

    isFetchingRemoteContent = true

    defer {
      isFetchingRemoteContent = false
      isLoading = false
    }

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

      BookmarkSyncQueue.shared.syncPending()

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

      let continueListeningByID = Dictionary(
        uniqueKeysWithValues: continueListeningBooks.map { ($0.id, $0) }
      )

      var books: [BookEntry] = []

      for progress in sortedProgress {
        guard books.count < 5 else { break }

        if let localBook = try? LocalBook.fetch(bookID: progress.bookID) {
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
