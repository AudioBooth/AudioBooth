import Audiobookshelf
import SwiftData
import SwiftUI

@MainActor
final class HomeViewModel: HomeView.Model {
  private var playerManager = PlayerManager.shared
  private var userProgressService = UserProgressService.shared
  private var recentItemsTask: Task<Void, Never>?

  private var recentlyPlayed: [RecentlyPlayedItem] = [] {
    didSet { refreshRecents() }
  }

  private var continueListening: [Book] = [] {
    didSet { refreshRecents() }
  }

  init() {
    super.init()
    setupRecentItemsObservation()
  }

  private func setupRecentItemsObservation() {
    recentItemsTask = Task {
      for await recents in RecentlyPlayedItem.observeAll() {
        guard !Task.isCancelled else { break }
        recentlyPlayed = recents
      }
    }
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
      if recent.playSessionInfo.isDownloaded || recent.timeListened != 0
        || PlayerManager.shared.current?.id == recent.bookID
      {
        recents.append(RecentRowModel(recent: recent))
      } else {
        try? recent.delete()
      }
    }

    self.recents = recents.sorted { lhs, rhs in
      switch (lhs.lastPlayedAt, rhs.lastPlayedAt) {
      case (.none, .none): false
      case (.some, .none): true
      case (.none, .some): false
      case let (.some(lhs), .some(rhs)): lhs > rhs
      }
    }
  }

  override func onAppear() {
    Task {
      await loadPersonalizedContent()
    }
  }

  override func refresh() async {
    await loadPersonalizedContent()
  }

  private func loadPersonalizedContent() async {
    isLoading = true

    do {
      async let personalizedTask = Audiobookshelf.shared.libraries.fetchPersonalized()
      async let userProgressTask = userProgressService.refresh()
      async let syncTask = syncRecentItemsProgress()

      let (personalized, _, _) = try await (personalizedTask, userProgressTask, syncTask)

      var sections = [Section]()
      for section in personalized {
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
          let series = items.map(SeriesCardModel.init)
          sections.append(.init(title: section.label, items: .series(series)))
        }
      }

      self.sections = sections
    } catch {
      print("Failed to fetch personalized content: \(error)")
      sections = []
    }

    isLoading = false
  }

  private func syncRecentItemsProgress() async {
    do {
      let recentItems = try RecentlyPlayedItem.fetchAll()
      let currentBookID = PlayerManager.shared.current?.id

      for item in recentItems {
        guard item.bookID != currentBookID,
          item.timeListened > 0
        else { continue }

        await syncItemProgress(item)
      }
    } catch {
      print("Failed to fetch recent items for sync: \(error)")
    }
  }

  private func syncItemProgress(_ item: RecentlyPlayedItem) async {
    let serverProgress = userProgressService.progressByBookID[item.bookID]
    let localCurrentTime = item.currentTime
    let serverCurrentTime = serverProgress?.currentTime ?? 0

    if localCurrentTime > serverCurrentTime {
      await syncWithSessionRecreation(item)
    } else {
      item.timeListened = 0
      print(
        "Local progress (\(localCurrentTime)s) <= server progress (\(serverCurrentTime)s) for book \(item.bookID), resetting timeListened"
      )
    }
  }

  private func syncWithSessionRecreation(_ item: RecentlyPlayedItem) async {
    do {
      let sessionInfo = item.playSessionInfo

      do {
        try await Audiobookshelf.shared.sessions.sync(
          sessionInfo.id,
          timeListened: item.timeListened,
          currentTime: item.currentTime
        )

        item.timeListened = 0
        print("Successfully synced progress for book \(item.bookID)")
      } catch {
        print("Session sync failed for book \(item.bookID): \(error)")

        do {
          print("Attempting to recreate session for book \(item.bookID)")
          let newSession = try await Audiobookshelf.shared.sessions.start(
            itemID: item.bookID,
            forceTranscode: false
          )

          let newSessionInfo = PlaySessionInfo(from: newSession)
          item.playSessionInfo.merge(with: newSessionInfo)

          try await Audiobookshelf.shared.sessions.sync(
            newSessionInfo.id,
            timeListened: item.timeListened,
            currentTime: item.currentTime
          )

          item.timeListened = 0
          print("Successfully recreated session and synced progress for book \(item.bookID)")
        } catch {
          print("Failed to recreate session and sync for book \(item.bookID): \(error)")
        }
      }
    }
  }
}
