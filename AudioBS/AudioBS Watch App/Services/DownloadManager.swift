import AVFoundation
import Audiobookshelf
import Combine
import Foundation
import Models

final class DownloadManager: NSObject, ObservableObject {
  static let shared = DownloadManager()

  private var audiobookshelf: Audiobookshelf { .shared }

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
  }

  @Published private(set) var downloads: [String: Bool] = [:]
  @Published private(set) var downloadProgress: [String: Double] = [:]

  private var downloadTasks: [String: Task<Void, Never>] = [:]
  private var urlSession: URLSession!
  private var activeDownloads: [URLSessionDownloadTask: (bookID: String, trackIndex: Int)] = [:]
  private var trackProgress: [String: [Int: Double]] = [:]

  override init() {
    super.init()
    let config = URLSessionConfiguration.background(
      withIdentifier: "me.jgrenier.AudioBS.watchkitapp")
    config.allowsExpensiveNetworkAccess = false
    config.httpMaximumConnectionsPerHost = 2
    config.isDiscretionary = false
    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

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
    downloadProgress[bookID] = 0.0

    var initialProgress: [Int: Double] = [:]
    for track in tracks {
      initialProgress[track.index] = 0.0
    }
    trackProgress[bookID] = initialProgress

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

          print(
            "Starting download of track \(track.index) (\(index + 1)/\(tracks.count)) at \(trackURL)"
          )

          let (tempURL, response) = try await downloadTrack(
            from: trackURL, bookID: bookID, trackIndex: track.index)

          guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
          }

          guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
          }

          guard let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
            contentType.lowercased().hasPrefix("audio/")
          else {
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
            track.relativePath = URL(string: "audiobooks/\(bookID)/\(track.index).\(fileExtension)")
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
          downloadProgress.removeValue(forKey: bookID)
          trackProgress.removeValue(forKey: bookID)
          print("Download completed successfully")

          NotificationCenter.default.post(
            name: Notification.Name("DownloadCompleted"), object: bookID)
        }

      } catch {
        print("Download failed: \(error)")
        await MainActor.run {
          downloads.removeValue(forKey: bookID)
          downloadProgress.removeValue(forKey: bookID)
          trackProgress.removeValue(forKey: bookID)
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
            track.relativePath = nil
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
              if let relativePath = track.relativePath {
                expectedFilenames.insert(relativePath.lastPathComponent)
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

  private func downloadTrack(
    from url: URL,
    bookID: String,
    trackIndex: Int
  ) async throws -> (URL, URLResponse) {
    return try await withCheckedThrowingContinuation { continuation in
      let task = urlSession.downloadTask(with: url)
      activeDownloads[task] = (bookID: bookID, trackIndex: trackIndex)

      task.resume()

      downloadCompletionHandlers[task] = { result in
        self.activeDownloads.removeValue(forKey: task)
        self.downloadCompletionHandlers.removeValue(forKey: task)
        continuation.resume(with: result)
      }
    }
  }

  private var downloadCompletionHandlers:
    [URLSessionDownloadTask: (Result<(URL, URLResponse), Error>) -> Void] = [:]

  private func updateOverallProgress(for bookID: String, totalTracks: Int) {
    guard let trackProgressDict = trackProgress[bookID] else { return }

    let totalProgress = trackProgressDict.values.reduce(0.0, +)
    let overallProgress = totalProgress / Double(totalTracks)

    DispatchQueue.main.async {
      self.downloadProgress[bookID] = overallProgress
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

extension DownloadManager: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let (bookID, trackIndex) = activeDownloads[downloadTask] else { return }

    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

    trackProgress[bookID]?[trackIndex] = progress

    if let totalTracks = trackProgress[bookID]?.count {
      updateOverallProgress(for: bookID, totalTracks: totalTracks)
      print(
        "Track \(trackIndex): \(String(format: "%.1f", progress * 100))% | Overall: \(String(format: "%.1f", (downloadProgress[bookID] ?? 0) * 100))%"
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let handler = downloadCompletionHandlers[downloadTask],
      let response = downloadTask.response
    else { return }

    handler(.success((location, response)))
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let downloadTask = task as? URLSessionDownloadTask,
      let handler = downloadCompletionHandlers[downloadTask]
    else { return }

    if let error = error {
      handler(.failure(error))
    }
  }
}
