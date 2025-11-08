import API
import AVFoundation
import Combine
import Foundation
import Models
import SwiftData

final class DownloadManager: NSObject, ObservableObject {
  static let shared = DownloadManager()

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
  }

  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "me.jgrenier.AudioBS.downloadQueue"
    return queue
  }()

  private var activeOperations: [String: DownloadOperation] = [:]
  private var progressTasks: [String: Task<Void, Never>] = [:]
  @Published private(set) var currentProgress: [String: Double] = [:]

  var backgroundCompletionHandler: (() -> Void)?

  func isDownloading(for bookID: String) -> Bool {
    activeOperations[bookID] != nil
  }

  func startDownload(for bookID: String) {
    guard activeOperations[bookID] == nil else { return }

    let operation = DownloadOperation(bookID: bookID)
    activeOperations[bookID] = operation
    currentProgress[bookID] = 0

    let progressTask = Task { @MainActor [weak self] in
      for await progress in operation.progress {
        guard !Task.isCancelled else { break }
        self?.currentProgress[bookID] = progress
      }
    }
    progressTasks[bookID] = progressTask

    operation.completionBlock = { @MainActor [weak self] in
      self?.progressTasks[bookID]?.cancel()
      self?.progressTasks.removeValue(forKey: bookID)
      self?.activeOperations.removeValue(forKey: bookID)
      self?.currentProgress.removeValue(forKey: bookID)
    }

    operationQueue.addOperation(operation)
  }

  func cancelDownload(for bookID: String) {
    activeOperations[bookID]?.cancel()
  }
}

extension DownloadManager {
  func deleteDownload(for bookID: String) {
    Task {
      guard
        let appGroupURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
        )
      else {
        Toast(error: "Failed to access app group container").show()
        return
      }

      let bookDirectory =
        appGroupURL
        .appendingPathComponent("audiobooks")
        .appendingPathComponent(bookID)

      do {
        if FileManager.default.fileExists(atPath: bookDirectory.path) {
          try FileManager.default.removeItem(at: bookDirectory)
        }

        if let item = try? LocalBook.fetch(bookID: bookID) {
          for track in item.orderedTracks {
            track.relativePath = nil
          }
          try? item.save()
        }
      } catch {
        Toast(error: "Failed to delete download: \(error.localizedDescription)").show()
      }
    }
  }

  func cleanupOrphanedDownloads() {
    Task {
      do {
        guard
          let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
          )
        else {
          return
        }

        let audiobooksDirectory = appGroupURL.appendingPathComponent("audiobooks")

        guard FileManager.default.fileExists(atPath: audiobooksDirectory.path) else {
          return
        }

        let validBookIDs = Set(try LocalBook.fetchAll().map { $0.bookID })

        let downloadDirectories = try FileManager.default.contentsOfDirectory(
          at: audiobooksDirectory, includingPropertiesForKeys: [.isDirectoryKey])

        for directory in downloadDirectories {
          let bookID = directory.lastPathComponent

          if !validBookIDs.contains(bookID) {
            try FileManager.default.removeItem(at: directory)
          }
        }
      } catch {}
    }
  }
}

private final class DownloadOperation: Operation, @unchecked Sendable {
  private var audiobookshelf: Audiobookshelf { .shared }

  let bookID: String
  let progress: AsyncStream<Double>

  private let progressContinuation: AsyncStream<Double>.Continuation

  private var book: LocalBook?
  private var session: Session?
  private var totalBytes: Int64 = 0
  private var bytesDownloadedSoFar: Int64 = 0

  private var currentTrack: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<Void, Error>?
  private var trackDestination: URL?

  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "me.jgrenier.AudioBS.download.\(bookID)")
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private var _executing = false {
    willSet {
      willChangeValue(forKey: "isExecuting")
    }
    didSet {
      didChangeValue(forKey: "isExecuting")
    }
  }

  private var _finished = false {
    willSet {
      willChangeValue(forKey: "isFinished")
    }
    didSet {
      didChangeValue(forKey: "isFinished")
    }
  }

  override var isAsynchronous: Bool { true }
  override var isExecuting: Bool { _executing }
  override var isFinished: Bool { _finished }

  init(bookID: String) {
    self.bookID = bookID

    let (stream, continuation) = AsyncStream.makeStream(
      of: Double.self, bufferingPolicy: .bufferingNewest(1))
    self.progress = stream
    self.progressContinuation = continuation

    super.init()
  }

  override func start() {
    guard !isCancelled else {
      finish(success: false, error: CancellationError())
      return
    }

    _executing = true

    Task {
      await executeDownload()
    }
  }

  override func cancel() {
    super.cancel()
    currentTrack?.cancel()
    progressContinuation.finish()

    Task {
      await cleanupPartialDownload()
    }
  }

  private func cleanupPartialDownload() async {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      return
    }

    let bookDirectory = appGroupURL.appendingPathComponent("audiobooks").appendingPathComponent(
      bookID)
    try? FileManager.default.removeItem(at: bookDirectory)
  }

  private func executeDownload() async {
    do {
      let playSession = try await audiobookshelf.sessions.start(
        itemID: bookID,
        isDownload: true
      )

      guard !isCancelled else {
        finish(success: false, error: CancellationError())
        return
      }

      guard let session = Session(from: playSession) else {
        finish(success: false, error: URLError(.badServerResponse))
        return
      }

      self.session = session

      let existingItem = try? LocalBook.fetch(bookID: bookID)
      let book = existingItem ?? LocalBook(from: playSession.libraryItem)
      self.book = book
      self.totalBytes = book.orderedTracks.reduce(0) { $0 + ($1.size ?? 0) }

      try await downloadTracks()

      try? book.save()
      finish(success: true, error: nil)
    } catch {
      finish(success: false, error: error)
    }
  }

  private func downloadTracks() async throws {
    guard let book, let session else { throw URLError(.unknown) }

    let tracks = book.orderedTracks
    guard !tracks.isEmpty else { throw URLError(.badURL) }

    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      throw URLError(.fileDoesNotExist)
    }

    var audiobooksDirectory = appGroupURL.appendingPathComponent("audiobooks")
    let bookDirectory = audiobooksDirectory.appendingPathComponent(bookID)

    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? audiobooksDirectory.setResourceValues(resourceValues)

    for track in tracks {
      guard !isCancelled else { throw CancellationError() }

      let trackURL = session.url(for: track)
      let fileExtension = track.ext ?? ".mp3"
      let trackFile = bookDirectory.appendingPathComponent("\(track.index)\(fileExtension)")

      try await withCheckedThrowingContinuation { continuation in
        let downloadTask = downloadSession.downloadTask(with: trackURL)
        downloadTask.countOfBytesClientExpectsToReceive = Int64(track.size ?? 500_000_000)

        self.currentTrack = downloadTask
        self.continuation = continuation
        self.trackDestination = trackFile

        downloadTask.resume()
      }

      track.relativePath = URL(string: "audiobooks/\(bookID)/\(track.index)\(fileExtension)")

      if let size = track.size {
        bytesDownloadedSoFar += size
      }
    }
  }

  private func finish(success: Bool, error: Error?) {
    _executing = false
    _finished = true

    progressContinuation.finish()

    if success {
      downloadSession.finishTasksAndInvalidate()
    } else {
      downloadSession.invalidateAndCancel()
    }

    if let session = session {
      Task {
        try await audiobookshelf.sessions.close(session.id)
      }
    }

    if success {
      Toast(success: "Download completed").show()
    } else if let error = error {
      let isCancelled = (error as? URLError)?.code == .cancelled || error is CancellationError
      if !isCancelled {
        Toast(error: "Download failed: \(error.localizedDescription)").show()
      }
    }
  }

  private func updateProgress(totalBytesWritten: Int64) {
    guard totalBytes > 0 else { return }
    let totalBytesDownloaded = bytesDownloadedSoFar + totalBytesWritten
    let newProgress = Double(totalBytesDownloaded) / Double(totalBytes)
    progressContinuation.yield(newProgress)
  }

  private func trackDownloadCompleted(location: URL) throws {
    guard let destination = trackDestination else {
      throw URLError(.cannotCreateFile)
    }

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }

    try FileManager.default.moveItem(at: location, to: destination)
    continuation?.resume()
  }
}

extension DownloadOperation: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard currentTrack == downloadTask else { return }
    updateProgress(totalBytesWritten: totalBytesWritten)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard
      let downloadTask = task as? URLSessionDownloadTask,
      currentTrack == downloadTask,
      continuation != nil
    else { return }

    if let error {
      continuation?.resume(throwing: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard currentTrack == downloadTask, continuation != nil else { return }

    do {
      try trackDownloadCompleted(location: location)
    } catch {
      continuation?.resume(throwing: error)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    if let completionHandler = DownloadManager.shared.backgroundCompletionHandler {
      DownloadManager.shared.backgroundCompletionHandler = nil
      completionHandler()
    }
  }
}
