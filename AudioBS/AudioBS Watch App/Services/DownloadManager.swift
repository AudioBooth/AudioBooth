import AVFoundation
import Audiobookshelf
import Combine
import Foundation
import Models

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
          }
        }

        await MainActor.run {
          downloads.removeValue(forKey: bookID)
          print("Download completed successfully")

          NotificationCenter.default.post(
            name: Notification.Name("DownloadCompleted"), object: bookID)
        }

      } catch {
        print("Download failed: \(error)")
        await MainActor.run {
          downloads.removeValue(forKey: bookID)
        }
      }

      downloadTasks.removeValue(forKey: bookID)
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
