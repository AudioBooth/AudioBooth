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

      await MainActor.run {
        startDownloadOperation(for: bookToSave)
      }
    }
  }

  private func startDownloadOperation(
    for book: WatchBook,
    reconnecting: Bool = false,
    onBackgroundEventsDelivered: (() -> Void)? = nil
  ) {
    let operation = DownloadOperation(
      book: book,
      localStorage: localStorage,
      reconnecting: reconnecting
    )
    operation.onBackgroundEventsDelivered = onBackgroundEventsDelivered
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
    currentProgress.removeValue(forKey: bookID)
  }

  func reconnectBackgroundSession(withIdentifier identifier: String, completion: @escaping () -> Void) {
    guard identifier.hasPrefix("me.jgrenier.AudioBS.watch.download.") else {
      completion()
      return
    }
    let bookID = String(identifier.dropFirst("me.jgrenier.AudioBS.watch.download.".count))

    guard activeOperations[bookID] == nil else {
      AppLogger.download.debug("Session already active for book: \(bookID)")
      completion()
      return
    }

    guard let book = localStorage.books.first(where: { $0.id == bookID }) else {
      AppLogger.download.warning("Cannot reconnect session for unknown book: \(bookID)")
      let config = URLSessionConfiguration.background(withIdentifier: identifier)
      let session = URLSession(configuration: config)
      session.invalidateAndCancel()
      completion()
      return
    }

    AppLogger.download.info("Reconnecting background session for book: \(bookID)")
    startDownloadOperation(for: book, reconnecting: true, onBackgroundEventsDelivered: completion)
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
      bookID
    )

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
        at: audiobooksDirectory,
        includingPropertiesForKeys: [.isDirectoryKey]
      )

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

  var onBackgroundEventsDelivered: (() -> Void)?

  private let progressContinuation: AsyncStream<Double>.Continuation
  private let localStorage: LocalBookStorage

  private var book: WatchBook
  private var totalBytes: Int64 = 0
  private var bytesDownloadedSoFar: Int64 = 0

  private var currentTrack: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<Void, Error>?

  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "me.jgrenier.AudioBS.watch.download.\(bookID)"
    )
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 14400
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

  private let isReconnecting: Bool
  private var hasResumedDownload = false

  init(
    book: WatchBook,
    localStorage: LocalBookStorage,
    reconnecting: Bool = false
  ) {
    self.book = book
    self.bookID = book.id
    self.localStorage = localStorage
    self.isReconnecting = reconnecting

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

    if isReconnecting {
      _ = downloadSession
      AppLogger.download.info("Reconnected to background session for \(self.bookID)")
    } else {
      Task {
        await executeDownload()
      }
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
      bookID
    )
    try? FileManager.default.removeItem(at: bookDirectory)
  }

  private func executeDownload() async {
    do {
      totalBytes = book.tracks.reduce(0) { $0 + ($1.size ?? 0) }

      try await downloadTracks()

      if let stored = localStorage.books.first(where: { $0.id == bookID }) {
        book.currentTime = stored.currentTime
      }
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

      if let relativePath = book.tracks.first(where: { $0.index == track.index })?.relativePath,
        FileManager.default.fileExists(
          atPath: documentsPath.appendingPathComponent(relativePath).path
        )
      {
        if let size = track.size {
          bytesDownloadedSoFar += size
        }
        continue
      }

      guard let downloadURL = track.url else {
        AppLogger.download.error("Track \(track.index) missing download URL")
        throw URLError(.badURL)
      }

      guard let fileExtension = track.ext, !fileExtension.isEmpty else {
        AppLogger.download.error("Track \(track.index) missing file extension, cannot download")
        throw URLError(.cannotDecodeContentData)
      }

      try await withCheckedThrowingContinuation { continuation in
        var request = URLRequest(url: downloadURL)
        for (key, value) in WatchConnectivityManager.shared.customHeaders {
          request.setValue(value, forHTTPHeaderField: key)
        }
        let downloadTask = downloadSession.downloadTask(with: request)
        downloadTask.taskDescription = "\(track.index)|\(fileExtension)"
        downloadTask.countOfBytesClientExpectsToReceive = Int64(track.size ?? 500_000_000)

        self.currentTrack = downloadTask
        self.continuation = continuation

        downloadTask.resume()
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
    } else if let error {
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

  private func saveCompletedDownload(_ downloadTask: URLSessionDownloadTask, location: URL) throws {
    guard
      let description = downloadTask.taskDescription,
      let separatorIndex = description.firstIndex(of: "|"),
      let trackIndex = Int(description[..<separatorIndex]),
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      throw URLError(.cannotCreateFile)
    }

    let fileExtension = String(description[description.index(after: separatorIndex)...])
    let relativePath = "audiobooks/\(bookID)/\(trackIndex)\(fileExtension)"
    let destination = documentsPath.appendingPathComponent(relativePath)

    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: location, to: destination)

    if let trackArrayIndex = book.tracks.firstIndex(where: { $0.index == trackIndex }) {
      book.tracks[trackArrayIndex].relativePath = relativePath
    }
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
    guard let error else { return }
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    if let httpResponse = downloadTask.response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      let statusDescription = HTTPURLResponse.localizedString(
        forStatusCode: httpResponse.statusCode
      ).capitalized
      let error = URLError(
        .badServerResponse,
        userInfo: [NSLocalizedDescriptionKey: statusDescription]
      )
      continuation?.resume(throwing: error)
      continuation = nil
      return
    }

    do {
      try saveCompletedDownload(downloadTask, location: location)
      continuation?.resume()
    } catch {
      continuation?.resume(throwing: error)
    }
    continuation = nil
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    if let onBackgroundEventsDelivered {
      self.onBackgroundEventsDelivered = nil
      Task { @MainActor in
        onBackgroundEventsDelivered()
      }
    }

    guard isReconnecting, !hasResumedDownload else { return }
    hasResumedDownload = true
    AppLogger.download.info("Background events delivered, resuming download for \(self.bookID)")
    Task {
      await executeDownload()
    }
  }
}
