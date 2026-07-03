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

  override func onKeepOfflineChanged() {
    KeepOfflineManager.shared.reconcile()
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

        if let books = try? context.fetch(FetchDescriptor<LocalBook>()) {
          for book in books where book.bookID != currentBookID {
            context.delete(book)
          }
        }

        if let podcasts = try? context.fetch(FetchDescriptor<LocalPodcast>()) {
          for podcast in podcasts {
            context.delete(podcast)
          }
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
    let breakdown = await computeContentBreakdown()

    totalSize = total.formattedByteSize
    downloadSize = downloads.formattedByteSize
    cacheSize = cache.formattedByteSize

    audiobooksBytes = breakdown.audiobooksBytes
    audiobooksCount = breakdown.audiobooksCount
    ebooksBytes = breakdown.ebooksBytes
    ebooksCount = breakdown.ebooksCount
    imageCacheBytes = cache
    totalBytes = total

    serverDownloads = buildServerDownloads()

    isLoading = false
  }

  private func computeContentBreakdown() async -> (
    audiobooksBytes: Int64, audiobooksCount: Int, ebooksBytes: Int64, ebooksCount: Int
  ) {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      return (0, 0, 0, 0)
    }

    var audiobooksBytes: Int64 = 0
    var audiobooksCount = 0
    var ebooksBytes: Int64 = 0
    var ebooksCount = 0

    let servers =
      (try? FileManager.default.contentsOfDirectory(
        at: appGroupURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    for server in servers {
      let audiobooksDir = server.appendingPathComponent("audiobooks")
      let ebooksDir = server.appendingPathComponent("ebooks")

      if let books = try? FileManager.default.contentsOfDirectory(at: audiobooksDir, includingPropertiesForKeys: nil) {
        for book in books {
          let size = directorySize(at: book)
          if size > 0 {
            audiobooksBytes += size
            audiobooksCount += 1
          }
        }
      }

      if let books = try? FileManager.default.contentsOfDirectory(at: ebooksDir, includingPropertiesForKeys: nil) {
        for book in books {
          let size = directorySize(at: book)
          if size > 0 {
            ebooksBytes += size
            ebooksCount += 1
          }
        }
      }
    }

    return (audiobooksBytes, audiobooksCount, ebooksBytes, ebooksCount)
  }

  private func buildServerDownloads() -> [StoragePreferencesView.ServerDownloads] {
    let servers = Audiobookshelf.shared.authentication.servers
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else { return [] }

    let sortedServers = servers.values.sorted {
      ($0.alias ?? $0.baseURL.host() ?? $0.id) < ($1.alias ?? $1.baseURL.host() ?? $1.id)
    }

    var result: [StoragePreferencesView.ServerDownloads] = []

    for server in sortedServers {
      let serverDir = appGroupURL.appendingPathComponent(server.id)
      let context = try? ModelContextProvider.shared.context(for: server.id)

      var bookIDs = Set<String>()
      let audiobooksDir = serverDir.appendingPathComponent("audiobooks")
      let ebooksDir = serverDir.appendingPathComponent("ebooks")

      if let dirs = try? FileManager.default.contentsOfDirectory(at: audiobooksDir, includingPropertiesForKeys: nil) {
        for dir in dirs where directorySize(at: dir) > 0 {
          bookIDs.insert(dir.lastPathComponent)
        }
      }
      if let dirs = try? FileManager.default.contentsOfDirectory(at: ebooksDir, includingPropertiesForKeys: nil) {
        for dir in dirs where directorySize(at: dir) > 0 {
          bookIDs.insert(dir.lastPathComponent)
        }
      }

      guard !bookIDs.isEmpty else { continue }

      let bookRows: [StoragePreferencesView.DownloadedBook] = bookIDs.sorted().map { bookID in
        let size = bookSize(bookID: bookID, serverID: server.id, appGroupURL: appGroupURL)
        let (title, author) = bookMetadata(bookID: bookID, context: context)
        return StoragePreferencesView.DownloadedBook(
          id: bookID,
          serverID: server.id,
          title: title,
          author: author,
          size: size.formattedByteSize
        )
      }

      let name = server.alias ?? server.baseURL.host() ?? server.id
      result.append(StoragePreferencesView.ServerDownloads(id: server.id, name: name, books: bookRows))
    }

    return result
  }

  private func bookMetadata(bookID: String, context: ModelContext?) -> (String, String?) {
    guard let context else { return (bookID, nil) }
    let predicate = #Predicate<LocalBook> { $0.bookID == bookID }
    let descriptor = FetchDescriptor<LocalBook>(predicate: predicate)
    guard let book = try? context.fetch(descriptor).first else { return (bookID, nil) }
    return (book.title, book.authors.first?.name)
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
