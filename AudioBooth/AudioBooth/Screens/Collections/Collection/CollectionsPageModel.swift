import API
import Combine
import Foundation
import Logging

final class CollectionsPageModel: CollectionsPage.Model {
  private var audiobookshelf: Audiobookshelf { Audiobookshelf.shared }

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 20
  private var loadTask: Task<Void, Never>?

  init(mode: CollectionMode) {
    let permissions = Audiobookshelf.shared.authentication.server?.permissions

    let canDelete: Bool

    switch mode {
    case .playlists:
      canDelete = true
    case .collections:
      canDelete = permissions?.delete == true
    }

    super.init(mode: mode, canDelete: canDelete)
  }

  override func onAppear() {
    Task {
      await refresh()
    }
  }

  override func refresh() async {
    loadTask?.cancel()
    loadTask = nil
    isLoadingNextPage = false
    currentPage = 0
    hasMorePages = false
    await loadCollections()
  }

  override func onDelete(at indexSet: IndexSet) {
    Task {
      for index in indexSet {
        let collection = collections[index]
        do {
          try await audiobookshelf.playlists.delete(playlistID: collection.id)
          collections.remove(at: index)
        } catch {
          AppLogger.viewModel.error("Failed to delete playlist: \(error)")
        }
      }
    }
  }

  override func loadNextPageIfNeeded() {
    guard loadTask == nil else { return }

    loadTask = Task {
      await loadCollections()
    }
  }

  private func loadCollections() async {
    guard !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0
    pageLoadFailed = false

    do {
      let collectionItems: [CollectionRow.Model]

      switch mode {
      case .playlists:
        let response = try await audiobookshelf.playlists.fetch(
          limit: itemsPerPage,
          page: currentPage
        )

        guard !Task.isCancelled else {
          isLoadingNextPage = false
          isLoading = false
          return
        }

        collectionItems = response.results.map { playlist in
          CollectionRowModel(collection: playlist)
        }

        hasMorePages = (currentPage + 1) * itemsPerPage < response.total

      case .collections:
        let response = try await audiobookshelf.collections.fetch(
          limit: itemsPerPage,
          page: currentPage
        )

        guard !Task.isCancelled else {
          isLoadingNextPage = false
          isLoading = false
          return
        }

        collectionItems = response.results.map { collection in
          CollectionRowModel(collection: collection)
        }

        hasMorePages = (currentPage + 1) * itemsPerPage < response.total
      }

      if currentPage == 0 {
        collections = collectionItems
      } else {
        collections.append(contentsOf: collectionItems)
      }

      currentPage += 1
    } catch {
      guard !Task.isCancelled else {
        isLoadingNextPage = false
        isLoading = false
        return
      }

      pageLoadFailed = true
      if currentPage == 0 {
        collections = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
    loadTask = nil
  }
}
