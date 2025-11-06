import API
import Combine
import Foundation

final class PlaylistsPageModel: PlaylistsPage.Model {
  private var audiobookshelf: Audiobookshelf { Audiobookshelf.shared }

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 20
  private var loadTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  init() {
    super.init()
    setupDeletionObserver()
  }

  private func setupDeletionObserver() {
    NotificationCenter.default.publisher(for: .playlistDeleted)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        guard let playlistID = notification.userInfo?["playlistID"] as? String else { return }
        self?.playlists.removeAll { $0.id == playlistID }
      }
      .store(in: &cancellables)
  }

  override func onAppear() {
    guard playlists.isEmpty else { return }

    loadTask = Task {
      await loadPlaylists()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    isLoadingNextPage = false
    currentPage = 0
    hasMorePages = false
    await loadPlaylists()
  }

  override func onDelete(at indexSet: IndexSet) {
    Task {
      for index in indexSet {
        let playlist = playlists[index]
        do {
          try await audiobookshelf.playlists.delete(playlistID: playlist.id)
          playlists.remove(at: index)
        } catch {
          print("Failed to delete playlist: \(error)")
        }
      }
    }
  }

  override func loadNextPageIfNeeded() {
    guard loadTask == nil else { return }

    loadTask = Task {
      await loadPlaylists()
    }
  }

  private func loadPlaylists() async {
    guard !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let response = try await audiobookshelf.playlists.fetch(
        limit: itemsPerPage,
        page: currentPage
      )

      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      let playlistItems = response.results.map { playlist in
        PlaylistRowModel(playlist: playlist)
      }

      if currentPage == 0 {
        playlists = playlistItems
      } else {
        playlists.append(contentsOf: playlistItems)
      }

      currentPage += 1
      hasMorePages = (currentPage * itemsPerPage) < response.total
    } catch {
      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      if currentPage == 0 {
        playlists = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
    loadTask = nil
  }
}

extension Notification.Name {
  static let playlistDeleted = Notification.Name("playlistDeleted")
}
