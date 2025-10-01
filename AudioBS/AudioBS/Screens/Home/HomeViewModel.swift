import Audiobookshelf
import Models
import SwiftData
import SwiftUI

final class HomeViewModel: HomeView.Model {
  private let downloadManager = DownloadManager.shared
  private var playerManager = PlayerManager.shared

  private var recentItemsTask: Task<Void, Never>?

  private var recentlyPlayed: [RecentlyPlayedItem] = []

  private var continueListening: [Book] = [] {
    didSet { refreshRecents() }
  }

  init() {
    super.init()
    setupRecentItemsObservation()
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
    recentlyPlayed = []
    continueListening = []
    sections = []
    recents = []
    isLoading = false

    if shouldRefresh {
      onAppear()
    }
  }
}

extension HomeViewModel {
  private func setupRecentItemsObservation() {
    recentItemsTask = Task { [weak self] in
      for await recents in RecentlyPlayedItem.observeAll() {
        guard !Task.isCancelled else { break }
        self?.recentlyPlayed = recents
        self?.syncRecents()
      }
    }
  }

  private func syncRecents() {
    let ids = Set(recentlyPlayed.map(\.bookID) + continueListening.map(\.id))

    recents.removeAll { recent in !ids.contains(recent.id) }

    let existingIDs = Set(recents.map(\.id))
    for recent in recentlyPlayed where !existingIDs.contains(recent.bookID) {
      recents.append(RecentRowModel(recent: recent))
    }

    recents.sort(by: >)
  }

  private func refreshRecents() {
    var recents: [RecentRowModel] = []

    var recentsByID = Dictionary(uniqueKeysWithValues: recentlyPlayed.map { ($0.bookID, $0) })

    for book in continueListening {
      if let recent = recentsByID[book.id] {
        recents.append(RecentRowModel(recent: recent))
        recentsByID.removeValue(forKey: book.id)
      } else {
        recents.append(
          RecentRowModel(
            book: book,
            onRemoved: { [weak self] in
              guard let self else { return }
              self.continueListening = self.continueListening.filter({ $0.id != book.id })
            }
          )
        )
      }
    }

    for recent in recentsByID.values {
      let progress = try? MediaProgress.fetch(bookID: recent.bookID)
      if downloadManager.downloads[recent.bookID] == true
        || recent.playSessionInfo.isDownloaded || (progress?.timeListened ?? 0) != 0
        || PlayerManager.shared.current?.id == recent.bookID
      {
        recents.append(RecentRowModel(recent: recent))
      } else {
        try? recent.delete()
      }
    }

    self.recents = recents.sorted(by: >)
  }

  private func processSections(_ personalizedSections: [Personalized.Section]) {
    var sections = [Section]()

    for section in personalizedSections {
      switch section.entities {
      case .books(let items):
        if section.id == "continue-listening" {
          continueListening = items
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

    self.sections = sections
  }

  private func syncRecentItemsProgress() async {
    do {
      let recentItems = try RecentlyPlayedItem.fetchAll()
      let currentBookID = PlayerManager.shared.current?.id

      for item in recentItems {
        let progress = try? MediaProgress.fetch(bookID: item.bookID)
        guard item.bookID != currentBookID,
          (progress?.timeListened ?? 0) > 0
        else { continue }

        await syncItemProgress(item)
      }
    } catch {
    }
  }
}

extension HomeViewModel {
  private func loadCachedContent() {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return
    }

    processSections(personalized.sections)
  }

  private func fetchRemoteContent() async {
    if sections.isEmpty {
      isLoading = true
    }

    do {
      async let progressSync: Void = MediaProgress.syncFromAPI()
      async let recentSync: Void = syncRecentItemsProgress()

      _ = try await (progressSync, recentSync)

      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      processSections(personalized.sections)
    } catch {
      print("Failed to fetch personalized content: \(error)")
    }

    isLoading = false
  }

  private func syncItemProgress(_ item: RecentlyPlayedItem) async {
    guard let localProgress = try? MediaProgress.fetch(bookID: item.bookID) else { return }

    if localProgress.timeListened > 0 {
      await syncWithSessionRecreation(item, progress: localProgress)
    }
  }

  private func syncWithSessionRecreation(_ item: RecentlyPlayedItem, progress: MediaProgress) async
  {
    do {
      let sessionInfo = item.playSessionInfo

      do {
        try await Audiobookshelf.shared.sessions.sync(
          sessionInfo.id,
          timeListened: progress.timeListened,
          currentTime: progress.currentTime
        )

        try? MediaProgress.updateProgress(
          for: item.bookID,
          currentTime: progress.currentTime,
          timeListened: 0,
          duration: progress.duration,
          progress: progress.progress
        )
      } catch {
        do {
          let newSession = try await Audiobookshelf.shared.sessions.start(
            itemID: item.bookID,
            forceTranscode: false
          )

          let newSessionInfo = PlaySessionInfo(from: newSession)
          item.playSessionInfo.merge(with: newSessionInfo)

          try await Audiobookshelf.shared.sessions.sync(
            newSessionInfo.id,
            timeListened: progress.timeListened,
            currentTime: progress.currentTime
          )

          try? MediaProgress.updateProgress(
            for: item.bookID,
            currentTime: progress.currentTime,
            timeListened: 0,
            duration: progress.duration,
            progress: progress.progress
          )
        } catch {}
      }
    }
  }
}
