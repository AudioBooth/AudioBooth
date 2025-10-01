import AVFoundation
import Audiobookshelf
import Combine
import Foundation
import Models
import SwiftData

final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()

  private var audiobookshelf: Audiobookshelf { .shared }

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
  }

  @Published private(set) var downloads: [String: Bool] = [:]

  private var downloadTasks: [String: Task<Void, Never>] = [:]

  func isDownloading(for bookID: String) -> Bool {
    return downloads[bookID] ?? false
  }

  func startDownload(for item: RecentlyPlayedItem) {
    let sessionInfo = item.playSessionInfo

    guard let tracks = sessionInfo.orderedTracks, let serverURL = audiobookshelf.serverURL
    else {
      print("Cannot start download: missing session info or tracks")
      Toast(error: "Cannot start download: missing session info").show()
      return
    }

    let bookID = item.bookID
    downloads[bookID] = true
    print("Starting download of \(tracks.count) tracks for book: \(item.title)")

    let task = Task {
      do {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          .first!
        let bookDirectory = documentsPath.appendingPathComponent("audiobooks")
          .appendingPathComponent(bookID)

        try FileManager.default.createDirectory(
          at: bookDirectory, withIntermediateDirectories: true)

        for (index, track) in tracks.enumerated() {
          let baseURL = serverURL.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
          let streamingPath = "/public/session/\(sessionInfo.id)/track/\(track.index)"
          guard let trackURL = URL(string: "\(baseURL)\(streamingPath)") else {
            print("Skipping track \(track.index) - invalid URL")
            continue
          }

          print("Starting download of track \(track.index) (\(index + 1)/\(tracks.count))")

          let (tempURL, response) = try await URLSession.shared.download(from: trackURL)

          guard let httpResponse = response as? HTTPURLResponse,
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
          else {
            print("ERROR: No Content-Type header for track \(track.index)")
            throw URLError(.badServerResponse)
          }

          let fileExtension = contentTypeToExtension(contentType)
          print("Content-Type: '\(contentType)' -> .\(fileExtension)")

          let trackFile = bookDirectory.appendingPathComponent(
            "\(track.index).\(fileExtension)")

          if FileManager.default.fileExists(atPath: trackFile.path) {
            try FileManager.default.removeItem(at: trackFile)
          }

          try FileManager.default.moveItem(at: tempURL, to: trackFile)

          await MainActor.run {
            track.fileName = "\(track.index).\(fileExtension)"
          }

          print(
            "Downloaded track \(track.index) (\(index + 1)/\(tracks.count)) to: \(trackFile.path)")
        }

        await MainActor.run {
          do {
            try item.save()
            print("Successfully saved download information to database")
          } catch {
            print("Failed to save download information: \(error)")
            Toast(error: "Failed to save download information").show()
          }
        }

        await MainActor.run {
          downloads.removeValue(forKey: bookID)
          print("Download completed successfully")
          Toast(success: "Download completed successfully").show()

          NotificationCenter.default.post(
            name: Notification.Name("DownloadCompleted"), object: bookID)
        }

      } catch {
        print("Download failed: \(error)")
        await MainActor.run {
          downloads.removeValue(forKey: bookID)
          Toast(error: "Download failed").show()
        }
      }

      downloadTasks.removeValue(forKey: bookID)
    }

    downloadTasks[bookID] = task
  }

  func startDownload(for book: Book) {
    let bookID = book.id
    downloads[bookID] = true
    print("Starting download for book: \(book.title)")

    let task = Task {
      do {
        let playSession = try await audiobookshelf.sessions.start(itemID: bookID)

        let recentItem = RecentlyPlayedItem(
          bookID: bookID,
          title: book.title,
          author: book.authorName,
          coverURL: book.coverURL,
          playSessionInfo: PlaySessionInfo(from: playSession)
        )

        try recentItem.save()

        startDownload(for: recentItem)

      } catch {
        await MainActor.run {
          downloads.removeValue(forKey: bookID)
          Toast(error: "Failed to start download: \(error.localizedDescription)").show()
          print("Failed to start download for book \(book.title): \(error)")
        }
      }
    }

    downloadTasks[bookID] = task
  }

  func cancelDownload(for bookID: String) {
    downloadTasks[bookID]?.cancel()
    downloadTasks.removeValue(forKey: bookID)
    downloads.removeValue(forKey: bookID)
    print("Download cancelled for book: \(bookID)")
  }

  func deleteDownload(for bookID: String) {
    Task {
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!
      let bookDirectory = documentsPath.appendingPathComponent("audiobooks").appendingPathComponent(
        bookID)

      do {
        print("Attempting to delete directory: \(bookDirectory.path)")

        if FileManager.default.fileExists(atPath: bookDirectory.path) {
          try FileManager.default.removeItem(at: bookDirectory)
          print("Successfully removed directory: \(bookDirectory.path)")
        } else {
          print("Directory does not exist: \(bookDirectory.path)")
        }

        if let item = try? RecentlyPlayedItem.fetch(bookID: bookID),
          let tracks = item.playSessionInfo.orderedTracks
        {
          for track in tracks {
            track.fileName = nil
          }
          try item.save()
          print("Successfully updated database to remove download information")
        }

        downloads.removeValue(forKey: bookID)
        print("Download deleted successfully for book: \(bookID)")
      } catch {
        print("Failed to delete download directory \(bookDirectory.path): \(error)")
        Toast(error: "Failed to delete download: \(error.localizedDescription)").show()
      }
    }
  }

  func cleanupOrphanedDownloads() {
    Task {
      do {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
          .first!
        let audiobooksDirectory = documentsPath.appendingPathComponent("audiobooks")

        guard FileManager.default.fileExists(atPath: audiobooksDirectory.path) else {
          print("Audiobooks directory does not exist, nothing to cleanup")
          return
        }

        var orphanedFilesCount = 0
        var orphanedDirectoriesCount = 0

        let downloadDirectories = try FileManager.default.contentsOfDirectory(
          at: audiobooksDirectory, includingPropertiesForKeys: [.isDirectoryKey])

        for directory in downloadDirectories {
          var isDirectory: ObjCBool = false
          FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)

          if isDirectory.boolValue {
            let bookID = directory.lastPathComponent

            guard
              let item = try? RecentlyPlayedItem.fetch(bookID: bookID),
              let tracks = item.playSessionInfo.orderedTracks
            else {
              try FileManager.default.removeItem(at: directory)
              orphanedDirectoriesCount += 1
              print("Removed orphaned directory for unknown book: \(bookID)")
              continue
            }

            var expectedFilenames = Set<String>()
            for track in tracks {
              if let fileName = track.fileName {
                expectedFilenames.insert(fileName)
              }
            }

            let filesInDirectory = try FileManager.default.contentsOfDirectory(
              at: directory, includingPropertiesForKeys: nil)

            for file in filesInDirectory {
              let filename = file.lastPathComponent

              if expectedFilenames.contains(filename) {
                print("Keep file: \(filename)")
              } else {
                try FileManager.default.removeItem(at: file)
                orphanedFilesCount += 1
                print("Removed orphaned file: \(filename)")
              }
            }

            let remainingFiles = try FileManager.default.contentsOfDirectory(
              at: directory, includingPropertiesForKeys: nil)
            if remainingFiles.isEmpty {
              try FileManager.default.removeItem(at: directory)
              orphanedDirectoriesCount += 1
              print("Removed empty directory: \(bookID)")
            }
          }
        }

        if orphanedFilesCount > 0 || orphanedDirectoriesCount > 0 {
          print(
            "Cleanup completed: removed \(orphanedFilesCount) orphaned files and \(orphanedDirectoriesCount) empty directories"
          )
        } else {
          print("No orphaned files or directories found")
        }

      } catch {
        print("Failed to cleanup orphaned downloads: \(error)")
      }
    }
  }

  private func contentTypeToExtension(_ contentType: String) -> String {
    switch contentType.lowercased() {
    case "audio/mpeg", "audio/mp3":
      return "mp3"
    case "audio/mp4", "audio/m4a", "audio/aac":
      return "m4a"
    case "audio/wav":
      return "wav"
    default:
      print("WARNING: Unknown Content-Type '\(contentType)', defaulting to mp3")
      return "mp3"
    }
  }
}
