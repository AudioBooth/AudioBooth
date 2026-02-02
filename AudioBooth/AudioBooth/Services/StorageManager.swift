import API
import Foundation
import Logging
import Models
import Nuke
import SwiftData

final class StorageManager {
  static let shared = StorageManager()

  private init() {}

  func getDownloadedContentSize() async -> Int64 {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      return 0
    }

    var totalSize: Int64 = 0

    do {
      let directories = try FileManager.default.contentsOfDirectory(
        at: appGroupURL,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )

      for directory in directories {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
          totalSize += calculateDirectorySize(at: directory)
        }
      }
    } catch {
      return 0
    }

    return totalSize
  }

  func getImageCacheSize() async -> Int64 {
    guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else {
      return 0
    }

    return await Task.detached {
      Int64(dataCache.totalSize)
    }.value
  }

  func getTotalStorageUsed() async -> Int64 {
    let downloadSize = await getDownloadedContentSize()
    let cacheSize = await getImageCacheSize()
    return downloadSize + cacheSize
  }

  func canDownload(additionalBytes: Int64 = 0) async -> Bool {
    let limit = UserPreferences.shared.maxDownloadStorage
    guard let maxBytes = limit.bytes else { return true }

    let currentUsage = await getDownloadedContentSize()
    return (currentUsage + additionalBytes) < maxBytes
  }

  @MainActor
  func cleanupUnusedDownloads() async {
    let setting = UserPreferences.shared.removeAfterUnused
    guard setting != .never else { return }

    let days = setting.rawValue
    let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let currentlyPlaying = PlayerManager.shared.current?.id

    AppLogger.download.info("Cleaning up downloads unused since \(cutoffDate)")

    let servers = Audiobookshelf.shared.authentication.servers

    for server in servers.values {
      do {
        let context = try ModelContextProvider.shared.context(for: server.id)

        let bookDescriptor = FetchDescriptor<LocalBook>()
        let allBooks = try context.fetch(bookDescriptor)
        let downloadedBooks = allBooks.filter { $0.isDownloaded }

        for book in downloadedBooks {
          if book.bookID == currentlyPlaying { continue }

          let bookID = book.bookID
          let progressPredicate = #Predicate<MediaProgress> { $0.bookID == bookID }
          let progressDescriptor = FetchDescriptor<MediaProgress>(predicate: progressPredicate)
          let progress = try? context.fetch(progressDescriptor).first

          let lastUsed = progress?.lastPlayedAt ?? book.createdAt

          if lastUsed < cutoffDate {
            AppLogger.download.info("Removing unused download: \(book.title) (last used: \(lastUsed))")
            DownloadManager.shared.deleteDownload(for: book.bookID)
          }
        }
      } catch {
        AppLogger.download.error("Failed to cleanup downloads for server \(server.id): \(error)")
      }
    }
  }

  func clearImageCache() async {
    ImagePipeline.shared.cache.removeAll()

    guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else {
      return
    }

    dataCache.removeAll()
    dataCache.flush()
    URLCache.shared.removeAllCachedResponses()
  }

  private func calculateDirectorySize(at url: URL) -> Int64 {
    var size: Int64 = 0

    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return 0
    }

    for case let fileURL as URL in enumerator {
      do {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        size += Int64(resourceValues.fileSize ?? 0)
      } catch {
        continue
      }
    }

    return size
  }
}

extension Int64 {
  var formattedByteSize: String {
    ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
  }
}
