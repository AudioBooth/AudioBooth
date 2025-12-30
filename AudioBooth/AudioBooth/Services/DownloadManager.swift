import API
import AVFoundation
import Combine
import Foundation
import Logging
import Models
import Pulse
import SwiftData

final class DownloadManager: NSObject, ObservableObject {
  static let shared = DownloadManager()

  enum DownloadType {
    case audiobook
    case ebook
  }

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

  func startDownload(for bookID: String, type: DownloadType = .audiobook) {
    guard activeOperations[bookID] == nil else { return }

    let operation = DownloadOperation(bookID: bookID, type: type)
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
        ),
        let serverID = Audiobookshelf.shared.authentication.server?.id
      else {
        Toast(error: "Failed to access app group container").show()
        return
      }

      guard let item = try? LocalBook.fetch(bookID: bookID) else {
        return
      }

      // Determine if this is an audiobook or ebook
      let isEbook = item.tracks.isEmpty
      let directory = isEbook ? "ebooks" : "audiobooks"

      let bookDirectory =
        appGroupURL
        .appendingPathComponent(serverID)
        .appendingPathComponent(directory)
        .appendingPathComponent(bookID)

      do {
        if FileManager.default.fileExists(atPath: bookDirectory.path) {
          try FileManager.default.removeItem(at: bookDirectory)
        }

        if isEbook {
          item.ebookFile = nil
        } else {
          for track in item.orderedTracks {
            track.relativePath = nil
          }
        }
        try? item.save()
      } catch {
        Toast(error: "Failed to delete download: \(error.localizedDescription)").show()
      }
    }
  }

  func deleteAllServerData() {
    Task {
      guard
        let appGroupURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
        )
      else {
        return
      }

      do {
        let directories = try FileManager.default.contentsOfDirectory(
          at: appGroupURL,
          includingPropertiesForKeys: [.isDirectoryKey]
        )

        for directory in directories {
          var isDirectory: ObjCBool = false
          FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)

          if isDirectory.boolValue {
            try? FileManager.default.removeItem(at: directory)
          }
        }

        AppLogger.download.info("Deleted all server data")
      } catch {
        AppLogger.download.error(
          "Failed to delete all server data: \(error.localizedDescription)"
        )
      }
    }
  }
}

private final class DownloadOperation: Operation, @unchecked Sendable {
  private var audiobookshelf: Audiobookshelf { .shared }

  let bookID: String
  let type: DownloadManager.DownloadType
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
      withIdentifier: "me.jgrenier.AudioBS.download.\(bookID)"
    )
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    let delegate = URLSessionProxyDelegate(delegate: self)
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

  init(bookID: String, type: DownloadManager.DownloadType) {
    self.bookID = bookID
    self.type = type

    let (stream, continuation) = AsyncStream.makeStream(
      of: Double.self,
      bufferingPolicy: .bufferingNewest(1)
    )
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
      ),
      let serverID = Audiobookshelf.shared.authentication.server?.id
    else {
      return
    }

    let directory = type == .audiobook ? "audiobooks" : "ebooks"
    let bookDirectory =
      appGroupURL
      .appendingPathComponent(serverID)
      .appendingPathComponent(directory)
      .appendingPathComponent(bookID)

    try? FileManager.default.removeItem(at: bookDirectory)
  }

  private func executeDownload() async {
    do {
      switch type {
      case .audiobook:
        try await executeAudiobookDownload()
      case .ebook:
        try await executeEbookDownload()
      }
      finish(success: true, error: nil)
    } catch {
      finish(success: false, error: error)
    }
  }

  private func executeAudiobookDownload() async throws {
    let playSession = try await audiobookshelf.sessions.start(
      itemID: bookID,
      sessionType: .download
    )

    guard !isCancelled else {
      throw CancellationError()
    }

    guard let session = Session(from: playSession) else {
      throw URLError(.badServerResponse)
    }

    self.session = session

    let existingItem = try? LocalBook.fetch(bookID: bookID)
    let book = existingItem ?? LocalBook(from: playSession.libraryItem)
    self.book = book
    self.totalBytes = book.orderedTracks.reduce(0) { $0 + ($1.size ?? 0) }
    try? book.save()

    try await downloadTracks()

    try? book.save()
  }

  private func executeEbookDownload() async throws {
    let book = try await audiobookshelf.books.fetch(id: bookID)

    guard let ebookURL = book.ebookURL else {
      throw URLError(.badURL)
    }

    let ext: String
    if let ebookFileExt = book.media.ebookFile?.metadata.ext {
      ext = ebookFileExt
    } else {
      let pathExt = ebookURL.pathExtension
      ext = pathExt.isEmpty ? ".epub" : ".\(pathExt)"
    }

    let existingItem = try? LocalBook.fetch(bookID: bookID)
    let localBook = existingItem ?? LocalBook(from: book)
    self.book = localBook
    try? localBook.save()

    try await downloadEbook(from: ebookURL, ext: ext)

    try? localBook.save()
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

    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      throw URLError(.userAuthenticationRequired)
    }

    let serverDirectory = appGroupURL.appendingPathComponent(serverID)
    var audiobooksDirectory = serverDirectory.appendingPathComponent("audiobooks")
    let bookDirectory = audiobooksDirectory.appendingPathComponent(bookID)

    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? audiobooksDirectory.setResourceValues(resourceValues)

    for track in tracks {
      guard !isCancelled else { throw CancellationError() }

      guard let ext = track.ext else { throw URLError(.badURL) }

      let trackURL = session.url(for: track)
      let trackFile = bookDirectory.appendingPathComponent("\(track.index)\(ext)")

      try await withCheckedThrowingContinuation { continuation in
        let downloadTask = downloadSession.downloadTask(with: trackURL)
        downloadTask.countOfBytesClientExpectsToReceive = Int64(track.size ?? 500_000_000)

        self.currentTrack = downloadTask
        self.continuation = continuation
        self.trackDestination = trackFile

        downloadTask.resume()
      }

      track.relativePath = URL(string: "\(serverID)/audiobooks/\(bookID)/\(track.index)\(ext)")

      if let size = track.size {
        bytesDownloadedSoFar += size
      }
    }
  }

  private func downloadEbook(from ebookURL: URL, ext: String) async throws {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      throw URLError(.fileDoesNotExist)
    }

    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      throw URLError(.userAuthenticationRequired)
    }

    let serverDirectory = appGroupURL.appendingPathComponent(serverID)
    var ebooksDirectory = serverDirectory.appendingPathComponent("ebooks")
    let bookDirectory = ebooksDirectory.appendingPathComponent(bookID)

    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? ebooksDirectory.setResourceValues(resourceValues)

    let ebookFile = bookDirectory.appendingPathComponent("\(bookID)\(ext)")

    try await withCheckedThrowingContinuation { continuation in
      let downloadTask = downloadSession.downloadTask(with: ebookURL)
      downloadTask.countOfBytesClientExpectsToReceive = 50_000_000

      self.currentTrack = downloadTask
      self.continuation = continuation
      self.trackDestination = ebookFile

      downloadTask.resume()
    }

    book?.ebookFile = URL(string: "\(serverID)/ebooks/\(bookID)/\(ebookFile.lastPathComponent)")
    progressContinuation.yield(1.0)
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

    if let session {
      Task {
        try await audiobookshelf.sessions.close(session.id)
      }
    }

    if success {
      Toast(success: "Download completed").show()
    } else if let error {
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
