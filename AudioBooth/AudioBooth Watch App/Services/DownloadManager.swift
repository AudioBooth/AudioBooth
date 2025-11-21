import Combine
import Foundation
import OSLog

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
    queue.name = "me.jgrenier.AudioBS.watch.downloadQueue"
    return queue
  }()

  private let localStorage = LocalBookStorage.shared
  private let connectivityManager = WatchConnectivityManager.shared

  private var activeOperations: [String: DownloadOperation] = [:]
  private var progressTasks: [String: Task<Void, Never>] = [:]
  @Published private(set) var currentProgress: [String: Double] = [:]

  func isDownloading(for bookID: String) -> Bool {
    activeOperations[bookID] != nil
  }

  func startDownload(for book: WatchBook) {
    guard activeOperations[book.id] == nil else { return }

    Task {
      guard
        let localBook = await connectivityManager.startSession(bookID: book.id, forDownload: true)
      else {
        AppLogger.download.error("Failed to get download info")
        return
      }

      var bookToSave = localBook
      bookToSave.currentTime = book.currentTime
      if bookToSave.coverURL == nil {
        bookToSave.coverURL = book.coverURL
      }
      localStorage.saveBook(bookToSave)

      var downloadURLs: [Int: URL] = [:]
      for track in localBook.tracks {
        if let url = track.url {
          downloadURLs[track.index] = url
        }
      }

      await MainActor.run {
        startDownloadOperation(for: bookToSave, downloadURLs: downloadURLs)
      }
    }
  }

  private func startDownloadOperation(for book: WatchBook, downloadURLs: [Int: URL]) {
    let operation = DownloadOperation(
      book: book,
      downloadURLs: downloadURLs,
      localStorage: localStorage
    )
    activeOperations[book.id] = operation
    currentProgress.removeValue(forKey: book.id)

    let progressTask = Task { @MainActor [weak self] in
      for await progress in operation.progress {
        guard !Task.isCancelled else { break }
        self?.currentProgress[book.id] = progress
      }
    }
    progressTasks[book.id] = progressTask

    operation.completionBlock = { @MainActor [weak self] in
      self?.progressTasks[book.id]?.cancel()
      self?.progressTasks.removeValue(forKey: book.id)
      self?.activeOperations.removeValue(forKey: book.id)
      self?.currentProgress.removeValue(forKey: book.id)
    }

    operationQueue.addOperation(operation)
  }

  func cancelDownload(for bookID: String) {
    activeOperations[bookID]?.cancel()
  }
}

extension DownloadManager {
  func deleteDownload(for bookID: String) {
    guard
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      return
    }

    let bookDirectory = documentsPath.appendingPathComponent("audiobooks").appendingPathComponent(
      bookID)

    do {
      if FileManager.default.fileExists(atPath: bookDirectory.path) {
        try FileManager.default.removeItem(at: bookDirectory)
      }

      localStorage.deleteBook(bookID)
    } catch {
      AppLogger.download.error("Failed to delete download: \(error.localizedDescription)")
    }
  }

  func cleanupOrphanedDownloads() {
    guard
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      return
    }

    let audiobooksDirectory = documentsPath.appendingPathComponent("audiobooks")

    guard FileManager.default.fileExists(atPath: audiobooksDirectory.path) else {
      AppLogger.download.debug("Audiobooks directory does not exist, nothing to cleanup")
      return
    }

    do {
      let downloadDirectories = try FileManager.default.contentsOfDirectory(
        at: audiobooksDirectory, includingPropertiesForKeys: [.isDirectoryKey])

      let localBooks = localStorage.books
      let localBookIDs = Set(localBooks.map { $0.id })

      for directory in downloadDirectories {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
          let bookID = directory.lastPathComponent

          if !localBookIDs.contains(bookID) {
            try FileManager.default.removeItem(at: directory)
            AppLogger.download.info("Removed orphaned directory for unknown book: \(bookID)")
          }
        }
      }
    } catch {
      AppLogger.download.error("Failed to cleanup orphaned downloads: \(error)")
    }
  }
}

private final class DownloadOperation: Operation, @unchecked Sendable {
  let bookID: String
  let progress: AsyncStream<Double>

  private let progressContinuation: AsyncStream<Double>.Continuation
  private let localStorage: LocalBookStorage
  private let downloadURLs: [Int: URL]

  private var book: WatchBook
  private var totalBytes: Int64 = 0
  private var bytesDownloadedSoFar: Int64 = 0

  private var currentTrack: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<Void, Error>?
  private var trackDestination: URL?

  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 3600
    config.allowsCellularAccess = true
    config.waitsForConnectivity = true
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private var _executing = false {
    willSet { willChangeValue(forKey: "isExecuting") }
    didSet { didChangeValue(forKey: "isExecuting") }
  }

  private var _finished = false {
    willSet { willChangeValue(forKey: "isFinished") }
    didSet { didChangeValue(forKey: "isFinished") }
  }

  override var isAsynchronous: Bool { true }
  override var isExecuting: Bool { _executing }
  override var isFinished: Bool { _finished }

  init(
    book: WatchBook,
    downloadURLs: [Int: URL],
    localStorage: LocalBookStorage
  ) {
    self.book = book
    self.bookID = book.id
    self.downloadURLs = downloadURLs
    self.localStorage = localStorage

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

    cleanupPartialDownload()
  }

  private func cleanupPartialDownload() {
    guard
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      return
    }

    let bookDirectory = documentsPath.appendingPathComponent("audiobooks").appendingPathComponent(
      bookID)
    try? FileManager.default.removeItem(at: bookDirectory)
  }

  private func executeDownload() async {
    do {
      totalBytes = book.tracks.reduce(0) { $0 + ($1.size ?? 0) }

      try await downloadTracks()

      localStorage.saveBook(book)
      finish(success: true, error: nil)
    } catch {
      finish(success: false, error: error)
    }
  }

  private func downloadTracks() async throws {
    let tracks = book.tracks.sorted { $0.index < $1.index }
    guard !tracks.isEmpty else { throw URLError(.badURL) }

    guard
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      throw URLError(.cannotCreateFile)
    }

    let bookDirectory = documentsPath.appendingPathComponent("audiobooks/\(bookID)")
    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    for track in tracks {
      guard !isCancelled else { throw CancellationError() }

      guard let downloadURL = downloadURLs[track.index] else {
        AppLogger.download.error("Track \(track.index) missing download URL")
        throw URLError(.badURL)
      }

      guard let fileExtension = track.ext, !fileExtension.isEmpty else {
        AppLogger.download.error("Track \(track.index) missing file extension, cannot download")
        throw URLError(.cannotDecodeContentData)
      }
      let trackFile = bookDirectory.appendingPathComponent("\(track.index)\(fileExtension)")

      try await withCheckedThrowingContinuation { continuation in
        let downloadTask = downloadSession.downloadTask(with: downloadURL)
        downloadTask.countOfBytesClientExpectsToReceive = Int64(track.size ?? 500_000_000)

        self.currentTrack = downloadTask
        self.continuation = continuation
        self.trackDestination = trackFile

        downloadTask.resume()
      }

      if let trackArrayIndex = book.tracks.firstIndex(where: { $0.index == track.index }) {
        book.tracks[trackArrayIndex].relativePath =
          "audiobooks/\(bookID)/\(track.index)\(fileExtension)"
      }

      if let size = track.size {
        bytesDownloadedSoFar += size
      }
    }
  }

  private func finish(success: Bool, error: Error?) {
    _executing = false
    _finished = true

    progressContinuation.finish()
    downloadSession.invalidateAndCancel()

    if success {
      AppLogger.download.info("Download completed for \(self.bookID)")
    } else if let error = error {
      let isCancelled = (error as? URLError)?.code == .cancelled || error is CancellationError
      if !isCancelled {
        AppLogger.download.error("Download failed: \(error.localizedDescription)")
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
}
