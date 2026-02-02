import API
import Foundation
import Models
import SwiftData

final class StoragePreferencesViewModel: StoragePreferencesView.Model {
  private let storageManager = StorageManager.shared

  override func onAppear() {
    Task {
      await loadStorageInfo()
    }
  }

  override func onClearDownloadsTapped() {
    showDownloadConfirmation = true
  }

  override func onClearCacheTapped() {
    showCacheConfirmation = true
  }

  override func onConfirmClearDownloads() {
    Task {
      isLoading = true
      let currentBookID = PlayerManager.shared.current?.id
      let servers = Audiobookshelf.shared.authentication.servers

      DownloadManager.shared.deleteAllServerData()

      for server in servers.values {
        guard let context = try? ModelContextProvider.shared.context(for: server.id) else { continue }
        let descriptor = FetchDescriptor<LocalBook>()
        guard let books = try? context.fetch(descriptor) else { continue }
        for book in books where book.bookID != currentBookID {
          context.delete(book)
        }
        try? context.save()
      }

      try? await Task.sleep(for: .seconds(0.5))
      await loadStorageInfo()
      Toast(success: "All downloads cleared").show()
    }
  }

  override func onConfirmClearCache() {
    Task {
      isLoading = true
      await storageManager.clearImageCache()
      try? await Task.sleep(for: .seconds(0.5))
      await loadStorageInfo()
      Toast(success: "Image cache cleared").show()
    }
  }

  override func onRemoveDownload(bookID: String, serverID: String) {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else { return }

    let serverDir = appGroupURL.appendingPathComponent(serverID)
    let audiobookDir = serverDir.appendingPathComponent("audiobooks").appendingPathComponent(bookID)
    let ebookDir = serverDir.appendingPathComponent("ebooks").appendingPathComponent(bookID)

    try? FileManager.default.removeItem(at: audiobookDir)
    try? FileManager.default.removeItem(at: ebookDir)

    if let context = try? ModelContextProvider.shared.context(for: serverID) {
      let predicate = #Predicate<LocalBook> { $0.bookID == bookID }
      let descriptor = FetchDescriptor<LocalBook>(predicate: predicate)
      if let book = try? context.fetch(descriptor).first {
        context.delete(book)
        try? context.save()
      }
    }

    DownloadManager.shared.downloadStates[bookID] = .notDownloaded

    Task {
      await loadStorageInfo()
    }
  }

  private func loadStorageInfo() async {
    isLoading = true

    let total = await storageManager.getTotalStorageUsed()
    let downloads = await storageManager.getDownloadedContentSize()
    let cache = await storageManager.getImageCacheSize()

    totalSize = total.formattedByteSize
    downloadSize = downloads.formattedByteSize
    cacheSize = cache.formattedByteSize

    serverDownloads = buildServerDownloads()

    isLoading = false
  }

  private func buildServerDownloads() -> [StoragePreferencesView.ServerDownloads] {
    let servers = Audiobookshelf.shared.authentication.servers
    let appGroupURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
    )

    var result: [StoragePreferencesView.ServerDownloads] = []
    let sortedServers = servers.values.sorted {
      ($0.alias ?? $0.baseURL.host() ?? $0.id) < ($1.alias ?? $1.baseURL.host() ?? $1.id)
    }

    for server in sortedServers {
      guard let context = try? ModelContextProvider.shared.context(for: server.id) else { continue }

      let descriptor = FetchDescriptor<LocalBook>()
      guard let books = try? context.fetch(descriptor) else { continue }

      let downloadedBooks = books.filter { $0.isDownloaded }
      guard !downloadedBooks.isEmpty else { continue }

      let bookRows: [StoragePreferencesView.DownloadedBook] = downloadedBooks.map { book in
        let size = bookSize(bookID: book.bookID, serverID: server.id, appGroupURL: appGroupURL)
        return StoragePreferencesView.DownloadedBook(
          id: book.bookID,
          serverID: server.id,
          title: book.title,
          author: book.authors.first?.name,
          size: size.formattedByteSize
        )
      }

      let name = server.alias ?? server.baseURL.host() ?? server.id
      result.append(
        StoragePreferencesView.ServerDownloads(
          id: server.id,
          name: name,
          books: bookRows
        )
      )
    }

    return result
  }

  private func bookSize(bookID: String, serverID: String, appGroupURL: URL?) -> Int64 {
    guard let appGroupURL else { return 0 }

    let serverDir = appGroupURL.appendingPathComponent(serverID)
    let audiobookDir = serverDir.appendingPathComponent("audiobooks").appendingPathComponent(bookID)
    let ebookDir = serverDir.appendingPathComponent("ebooks").appendingPathComponent(bookID)

    return directorySize(at: audiobookDir) + directorySize(at: ebookDir)
  }

  private func directorySize(at url: URL) -> Int64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
      size += Int64(values?.fileSize ?? 0)
    }
    return size
  }
}
