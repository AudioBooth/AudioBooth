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

  static let appGroupIdentifier = "group.me.jgrenier.audioBS"

  static let backgroundSessionPrefix = "me.jgrenier.AudioBS.download."

  static let appGroupContainer: URL = {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
      fatalError("App group container '\(appGroupIdentifier)' not configured")
    }
    return url
  }()

  static func serverDirectory(serverID: String) -> URL {
    appGroupContainer.appendingPathComponent(serverID)
  }

  static func audiobookDirectory(serverID: String, bookID: String) -> URL {
    serverDirectory(serverID: serverID).appendingPathComponent("audiobooks").appendingPathComponent(bookID)
  }

  static func ebookDirectory(serverID: String, bookID: String) -> URL {
    serverDirectory(serverID: serverID).appendingPathComponent("ebooks").appendingPathComponent(bookID)
  }

  static func episodeDirectory(serverID: String, podcastID: String, episodeID: String) -> URL {
    serverDirectory(serverID: serverID)
      .appendingPathComponent("episodes")
      .appendingPathComponent(podcastID)
      .appendingPathComponent(episodeID)
  }

  enum DownloadType: Equatable {
    case book
    case ebook
    case episode(podcastID: String, episodeID: String)
  }

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
  }

  struct DownloadInfo {
    let title: String
    let coverURL: URL?
    let duration: Double?
    let size: Int64?
    let startedAt: Date
  }

  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "me.jgrenier.AudioBS.downloadQueue"
    return queue
  }()

  private var activeOperations: [String: DownloadOperation] = [:]
  private var progressCancellables: [String: AnyCancellable] = [:]
  @Published var downloadStates: [String: DownloadState] = [:]
  @Published var downloadInfos: [String: DownloadInfo] = [:]

  var backgroundCompletionHandler: (() -> Void)?

  override init() {
    super.init()
    updateDownloadStates()
  }

  func updateDownloadStates() {
    guard Audiobookshelf.shared.libraries.current != nil else { return }

    if let books = try? LocalBook.fetchAll() {
      for book in books {
        downloadStates[book.bookID] = book.isDownloaded ? .downloaded : .notDownloaded
      }
    }

    if let episodes = try? LocalEpisode.fetchAll() {
      for episode in episodes {
        downloadStates[episode.episodeID] = episode.isDownloaded ? .downloaded : .notDownloaded
      }
    }
  }

  func isDownloading(for bookID: String) -> Bool {
    activeOperations[bookID] != nil
  }

  func startDownload(
    for bookID: String,
    type: DownloadType = .book,
    info: DownloadInfo? = nil,
  ) {
    guard activeOperations[bookID] == nil else {
      return
    }

    if type != .ebook, downloadStates[bookID] == .downloaded {
      return
    }

    AppLogger.download.info("Starting \(type) download for book: \(bookID)")
    let wasDownloaded = downloadStates[bookID] == .downloaded
    let operation = DownloadOperation(bookID: bookID, type: type)
    activeOperations[bookID] = operation

    Task { @MainActor [weak self] in
      self?.downloadStates[bookID] = .downloading(progress: 0)
      if let info {
        self?.downloadInfos[bookID] = info
      }
    }

    let progressCancellable = operation.progressSubject
      .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] progress in
        self?.downloadStates[bookID] = .downloading(progress: progress)
      }
    progressCancellables[bookID] = progressCancellable

    operation.completionBlock = { [weak self] in
      Task { @MainActor in
        self?.progressCancellables[bookID]?.cancel()
        self?.progressCancellables.removeValue(forKey: bookID)
        self?.activeOperations.removeValue(forKey: bookID)
        self?.downloadInfos.removeValue(forKey: bookID)

        if operation.isFinished && !operation.isCancelled {
          AppLogger.download.info("Download completed successfully for book: \(bookID)")
          self?.downloadStates[bookID] =
            operation.resultIsFullyDownloaded || wasDownloaded ? .downloaded : .notDownloaded
        } else {
          AppLogger.download.info("Download cancelled or failed for book: \(bookID)")
          self?.downloadStates[bookID] = wasDownloaded ? .downloaded : .notDownloaded
        }
      }
    }

    operationQueue.addOperation(operation)
  }

  func cancelDownload(for bookID: String) {
    AppLogger.download.info("Cancelling download for book: \(bookID)")
    activeOperations[bookID]?.cancel()

    Task { @MainActor in
      downloadStates[bookID] = .notDownloaded
      downloadInfos.removeValue(forKey: bookID)
    }
  }

  func handleBackgroundSessionEvents(identifier: String, completionHandler: @escaping () -> Void) {
    backgroundCompletionHandler = completionHandler

    let bookID = identifier.replacingOccurrences(of: Self.backgroundSessionPrefix, with: "")
    guard activeOperations[bookID] == nil else { return }

    AppLogger.download.info("Reconnecting to orphaned background session: \(identifier)")
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    _ = URLSession(
      configuration: config,
      delegate: OrphanedDownloadSessionDelegate(),
      delegateQueue: nil
    )
  }
}

private final class OrphanedDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    try? FileManager.default.removeItem(at: location)
  }

  nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    session.finishTasksAndInvalidate()
    Task { @MainActor in
      let manager = DownloadManager.shared
      manager.backgroundCompletionHandler?()
      manager.backgroundCompletionHandler = nil
    }
  }
}

extension DownloadManager {
  func deleteDownload(for bookID: String) {
    Task {
      guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
        AppLogger.download.error("No active server for deletion")
        Toast(error: "No active server").show()
        return
      }

      try? FileManager.default.removeItem(at: Self.audiobookDirectory(serverID: serverID, bookID: bookID))
      try? FileManager.default.removeItem(at: Self.ebookDirectory(serverID: serverID, bookID: bookID))

      if let item = try? LocalBook.fetch(bookID: bookID) {
        try? item.delete()
      }

      Task { @MainActor in
        downloadStates[bookID] = .notDownloaded
      }

      AppLogger.download.info("Deleted download for book: \(bookID)")
    }
  }

  func deleteEpisodeDownload(episodeID: String, podcastID: String) {
    Task {
      guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
        AppLogger.download.error("No active server for deletion")
        Toast(error: "No active server").show()
        return
      }

      try? FileManager.default.removeItem(
        at: Self.episodeDirectory(serverID: serverID, podcastID: podcastID, episodeID: episodeID)
      )

      if let episode = try? LocalEpisode.fetch(episodeID: episodeID) {
        try? episode.delete()
      }

      Task { @MainActor in
        downloadStates[episodeID] = .notDownloaded
      }

      AppLogger.download.info("Deleted download for episode: \(episodeID)")
    }
  }

  func removeCompleted() {
    guard UserPreferences.shared.removeDownloadOnCompletion else { return }

    let currentPlayingID = PlayerManager.shared.current?.id

    for (bookID, state) in downloadStates {
      guard state == .downloaded, bookID != currentPlayingID else { continue }
      guard let progress = try? MediaProgress.fetch(bookID: bookID), progress.isFinished else { continue }
      deleteDownload(for: bookID)
    }
  }

  func deleteAllServerData() {
    Task {
      do {
        let directories = try FileManager.default.contentsOfDirectory(
          at: Self.appGroupContainer,
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
  private(set) var resultIsFullyDownloaded: Bool = false
  private var ebookStepCompleted = false
  private var audioStepCompleted = false
  let progressSubject = PassthroughSubject<Double, Never>()

  private var totalBytes: Int64 = 0
  private var bytesDownloadedSoFar: Int64 = 0

  private let maxRetryAttempts = 3

  private struct FileDownload {
    let request: URLRequest
    let expectedSize: Int64
    let destination: URL
  }

  private struct ActiveDownload {
    let file: FileDownload
    let attempt: Int
    let task: URLSessionDownloadTask
  }

  private var activeDownloads: [Int: ActiveDownload] = [:]
  private var taskBytesWritten: [Int: Int64] = [:]
  private var batchContinuation: CheckedContinuation<Void, Error>?
  private let continuationLock = NSLock()

  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: DownloadManager.backgroundSessionPrefix + bookID
    )
    config.timeoutIntervalForRequest = 300
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
    AppLogger.download.info("Cancelling download for book: \(bookID)")
    super.cancel()
    completeBatch(with: CancellationError())
    progressSubject.send(completion: .finished)

    Task {
      await cleanupPartialDownload()
    }
  }

  private func cleanupPartialDownload() async {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else { return }

    switch type {
    case .book:
      if !audioStepCompleted {
        try? FileManager.default.removeItem(at: DownloadManager.audiobookDirectory(serverID: serverID, bookID: bookID))
      }
      if !ebookStepCompleted {
        try? FileManager.default.removeItem(at: DownloadManager.ebookDirectory(serverID: serverID, bookID: bookID))
      }
    case .ebook:
      if !ebookStepCompleted {
        try? FileManager.default.removeItem(at: DownloadManager.ebookDirectory(serverID: serverID, bookID: bookID))
      }
    case .episode(let podcastID, let episodeID):
      try? FileManager.default.removeItem(
        at: DownloadManager.episodeDirectory(serverID: serverID, podcastID: podcastID, episodeID: episodeID)
      )
    }
  }

  private func executeDownload() async {
    do {
      switch type {
      case .book, .ebook:
        try await executeBookDownload()
      case .episode(let podcastID, let episodeID):
        try await executeEpisodeDownload(podcastID: podcastID, episodeID: episodeID)
      }
      finish(success: true, error: nil)
    } catch {
      AppLogger.download.error("Download failed for book \(bookID): \(error.localizedDescription)")
      finish(success: false, error: error)
    }
  }

  private func executeBookDownload() async throws {
    let book = try await audiobookshelf.books.fetch(id: bookID)

    let serverHasAudio = book.mediaType.contains(.audiobook) && !(book.tracks ?? []).isEmpty
    let serverHasEbook = book.mediaType.contains(.ebook)

    let wantsAudio = type == .book && serverHasAudio
    let wantsEbook = (type == .book || type == .ebook) && serverHasEbook

    guard wantsAudio || wantsEbook else {
      AppLogger.download.error("Nothing to download for book \(bookID)")
      throw URLError(.badURL)
    }

    totalBytes = 0
    if wantsAudio {
      totalBytes += (book.tracks ?? []).reduce(0) { $0 + ($1.metadata?.size ?? 0) }
    }
    if wantsEbook, let ebookSize = book.media.ebookFile?.metadata.size {
      totalBytes += ebookSize
    }

    if wantsEbook {
      guard !isCancelled else { throw CancellationError() }
      try await downloadEbookStep(book: book)
    }

    if wantsAudio {
      guard !isCancelled else { throw CancellationError() }
      try await downloadAudiobookStep(book: book)
    }

    switch type {
    case .book:
      resultIsFullyDownloaded = true
    case .ebook:
      resultIsFullyDownloaded = !serverHasAudio
    case .episode:
      break
    }

    if resultIsFullyDownloaded {
      progressSubject.send(1.0)
    }
  }

  private func downloadAudiobookStep(book: Book) async throws {
    let trackCount = book.tracks?.count ?? 0
    let stepBytes = (book.tracks ?? []).reduce(0) { $0 + ($1.metadata?.size ?? 0) }
    AppLogger.download.info("Downloading audiobook: \(trackCount) tracks, \(stepBytes.formattedByteSize)")

    let tracks = try await downloadTracks(book: book)

    let localBook = LocalBook(from: book)
    localBook.tracks = tracks
    try? localBook.save()

    audioStepCompleted = true
  }

  private func downloadEbookStep(book: Book) async throws {
    guard let ebookURL = book.ebookURL else {
      AppLogger.download.error("No ebook URL found for book: \(bookID)")
      throw URLError(.badURL)
    }

    let ext: String
    if let ebookFileExt = book.media.ebookFile?.metadata.ext {
      ext = ebookFileExt
    } else {
      let pathExt = ebookURL.pathExtension
      ext = pathExt.isEmpty ? ".epub" : ".\(pathExt)"
    }

    AppLogger.download.info("Downloading ebook: \(ext)")
    let ebookExpectedSize = book.media.ebookFile?.metadata.size ?? 50_000_000
    _ = try await downloadEbook(from: ebookURL, ext: ext, expectedSize: ebookExpectedSize)

    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      throw URLError(.userAuthenticationRequired)
    }

    let localBook = LocalBook(from: book)
    localBook.ebookFile = URL(string: "\(serverID)/ebooks/\(bookID)/\(bookID)\(ext)")
    try? localBook.save()
    ebookStepCompleted = true

  }

  private func executeEpisodeDownload(podcastID: String, episodeID: String) async throws {
    let podcast = try await audiobookshelf.podcasts.fetch(id: podcastID)
    guard !isCancelled else { throw CancellationError() }

    guard let apiEpisode = podcast.media.episodes?.first(where: { $0.id == episodeID }) else {
      AppLogger.download.error("Episode not found: \(episodeID)")
      throw URLError(.badURL)
    }

    guard let audioTrack = apiEpisode.audioTrack, let ino = audioTrack.ino else {
      AppLogger.download.error("No audio track for episode: \(episodeID)")
      throw URLError(.badURL)
    }

    let fileSize = audioTrack.metadata?.size ?? apiEpisode.size ?? 0
    self.totalBytes = fileSize
    AppLogger.download.info("Downloading episode: \(apiEpisode.title), \(fileSize.formattedByteSize)")

    let context = try await currentServerContext()
    let episodeDirectory = DownloadManager.episodeDirectory(
      serverID: context.serverID,
      podcastID: podcastID,
      episodeID: episodeID
    )
    try prepareDownloadDirectory(episodeDirectory)

    let ext = audioTrack.sanitizedExt
    let trackURL = context.serverURL.appendingPathComponent("api/items/\(podcastID)/file/\(ino)/download")
    let trackFile = episodeDirectory.appendingPathComponent("0\(ext)")

    try await downloadFiles([
      FileDownload(
        request: authorizedRequest(url: trackURL, credentials: context.credentials),
        expectedSize: fileSize,
        destination: trackFile
      )
    ])

    let localPodcast: LocalPodcast
    if let existing = try? LocalPodcast.fetch(podcastID: podcastID) {
      existing.title = podcast.title
      existing.author = podcast.author
      existing.coverURL = podcast.coverURL()
      existing.podcastDescription = podcast.description
      existing.genres = podcast.genres
      existing.feedURL = podcast.feedURL
      existing.language = podcast.language
      existing.podcastType = podcast.podcastType
      localPodcast = existing
    } else {
      localPodcast = LocalPodcast(from: podcast)
    }
    try? localPodcast.save()

    let localEpisode = LocalEpisode(
      episodeID: episodeID,
      podcast: localPodcast,
      title: apiEpisode.title,
      duration: apiEpisode.duration ?? 0,
      season: apiEpisode.season,
      episode: apiEpisode.episode,
      episodeDescription: apiEpisode.description,
      publishedAt: apiEpisode.publishedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
      coverURL: podcast.coverURL(),
      track: Track(
        index: 0,
        startOffset: 0,
        duration: apiEpisode.duration ?? 0,
        filename: audioTrack.metadata?.filename,
        ext: ext,
        size: fileSize,
        relativePath: URL(string: "\(context.serverID)/episodes/\(podcastID)/\(episodeID)/0\(ext)")
      ),
      chapters: (apiEpisode.chapters ?? []).map {
        Chapter(id: $0.id, start: $0.start, end: $0.end, title: $0.title)
      }
    )
    try? localEpisode.save()

    resultIsFullyDownloaded = true
    progressSubject.send(1.0)
  }

  private func downloadTracks(book: Book) async throws -> [Track] {
    let apiTracks = book.tracks ?? []
    guard !apiTracks.isEmpty else {
      AppLogger.download.error("No tracks found for audiobook: \(bookID)")
      throw URLError(.badURL)
    }

    let context = try await currentServerContext()
    let bookDirectory = DownloadManager.audiobookDirectory(serverID: context.serverID, bookID: bookID)
    try prepareDownloadDirectory(bookDirectory)

    var tracks: [Track] = []
    var files: [FileDownload] = []

    for apiTrack in apiTracks {
      guard !isCancelled else { throw CancellationError() }
      guard let ino = apiTrack.ino else { continue }

      let ext = apiTrack.sanitizedExt
      let trackURL = context.serverURL.appendingPathComponent("api/items/\(bookID)/file/\(ino)/download")
      let trackFile = bookDirectory.appendingPathComponent("\(apiTrack.index)\(ext)")

      files.append(
        FileDownload(
          request: authorizedRequest(url: trackURL, credentials: context.credentials),
          expectedSize: apiTrack.metadata?.size ?? 500_000_000,
          destination: trackFile
        )
      )

      let track = Track(from: apiTrack)
      track.relativePath = URL(string: "\(context.serverID)/audiobooks/\(bookID)/\(apiTrack.index)\(ext)")
      tracks.append(track)
    }

    try await downloadFiles(files)
    return tracks
  }

  private func downloadEbook(from ebookURL: URL, ext: String, expectedSize: Int64) async throws -> URL {
    let context = try await currentServerContext()
    let bookDirectory = DownloadManager.ebookDirectory(serverID: context.serverID, bookID: bookID)
    try prepareDownloadDirectory(bookDirectory)

    let ebookFile = bookDirectory.appendingPathComponent("\(bookID)\(ext)")

    try await downloadFiles([
      FileDownload(
        request: authorizedRequest(url: ebookURL, credentials: context.credentials),
        expectedSize: expectedSize,
        destination: ebookFile
      )
    ])

    return ebookFile
  }

  private func diskSize(of url: URL) -> Int64 {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.size] as? Int64) ?? 0
  }

  private struct ServerContext {
    let serverID: String
    let serverURL: URL
    let credentials: Credentials
  }

  private func currentServerContext() async throws -> ServerContext {
    guard
      let server = Audiobookshelf.shared.authentication.server,
      let serverURL = Audiobookshelf.shared.authentication.serverURL,
      let credentials = try? await server.freshToken
    else {
      AppLogger.download.error("Missing authentication credentials")
      throw URLError(.userAuthenticationRequired)
    }
    return ServerContext(serverID: server.id, serverURL: serverURL, credentials: credentials)
  }

  private func prepareDownloadDirectory(_ url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try? FileManager.default.removeItem(at: url)
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

    var parent = url.deletingLastPathComponent()
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? parent.setResourceValues(values)
  }

  private func authorizedRequest(url: URL, credentials: Credentials) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(credentials.bearer, forHTTPHeaderField: "Authorization")
    if let customHeaders = Audiobookshelf.shared.authentication.server?.customHeaders {
      for (key, value) in customHeaders {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }
    return request
  }

  private func downloadFiles(_ files: [FileDownload]) async throws {
    guard !files.isEmpty else { return }
    guard !isCancelled else { throw CancellationError() }

    let isStreaming = await MainActor.run {
      guard let current = PlayerManager.shared.current else { return false }
      return current.isPlaying && current.downloadState == .notDownloaded
    }
    let priority = isStreaming ? URLSessionTask.lowPriority : URLSessionTask.defaultPriority

    try await withCheckedThrowingContinuation { continuation in
      continuationLock.lock()
      batchContinuation = continuation
      let tasks = files.map { makeDownloadTask(for: $0, attempt: 0, priority: priority) }
      continuationLock.unlock()

      AppLogger.download.info("Queued \(tasks.count) background download tasks for book: \(bookID)")
      for task in tasks {
        task.resume()
      }
    }
  }

  private func makeDownloadTask(
    for file: FileDownload,
    attempt: Int,
    priority: Float,
    resumeData: Data? = nil
  ) -> URLSessionDownloadTask {
    let task: URLSessionDownloadTask
    if let resumeData {
      task = downloadSession.downloadTask(withResumeData: resumeData)
    } else {
      task = downloadSession.downloadTask(with: file.request)
    }
    task.countOfBytesClientExpectsToReceive = file.expectedSize > 0 ? file.expectedSize : 500_000_000
    task.priority = priority
    activeDownloads[task.taskIdentifier] = ActiveDownload(file: file, attempt: attempt, task: task)
    return task
  }

  private func retry(_ task: URLSessionDownloadTask, after error: Error) {
    continuationLock.lock()
    guard let activeDownload = activeDownloads[task.taskIdentifier] else {
      continuationLock.unlock()
      return
    }

    let nextAttempt = activeDownload.attempt + 1
    guard nextAttempt < maxRetryAttempts, !isCancelled else {
      continuationLock.unlock()
      completeBatch(with: error)
      return
    }
    continuationLock.unlock()

    let delay = pow(2.0, Double(nextAttempt))
    AppLogger.download.info(
      "Retry \(nextAttempt)/\(maxRetryAttempts - 1) after \(delay)s for \(activeDownload.file.request.url?.lastPathComponent ?? "unknown")"
    )

    Task {
      try? await Task.sleep(for: .seconds(delay))
      guard !self.isCancelled else {
        self.completeBatch(with: CancellationError())
        return
      }

      let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
      let retryTask = self.withDownloadStateLock { () -> URLSessionDownloadTask? in
        guard self.activeDownloads.removeValue(forKey: task.taskIdentifier) != nil else {
          return nil
        }
        self.taskBytesWritten.removeValue(forKey: task.taskIdentifier)
        return self.makeDownloadTask(
          for: activeDownload.file,
          attempt: nextAttempt,
          priority: task.priority,
          resumeData: resumeData
        )
      }
      retryTask?.resume()
    }
  }

  private func complete(_ task: URLSessionDownloadTask, at location: URL) throws {
    continuationLock.lock()
    guard let activeDownload = activeDownloads[task.taskIdentifier] else {
      continuationLock.unlock()
      return
    }
    continuationLock.unlock()

    if FileManager.default.fileExists(atPath: activeDownload.file.destination.path) {
      try FileManager.default.removeItem(at: activeDownload.file.destination)
    }
    try FileManager.default.moveItem(at: location, to: activeDownload.file.destination)

    continuationLock.lock()
    activeDownloads.removeValue(forKey: task.taskIdentifier)
    taskBytesWritten.removeValue(forKey: task.taskIdentifier)
    bytesDownloadedSoFar += diskSize(of: activeDownload.file.destination)
    let continuation = activeDownloads.isEmpty ? takeBatchContinuationLocked() : nil
    continuationLock.unlock()
    continuation?.resume()
  }

  private func completeBatch(with error: Error) {
    continuationLock.lock()
    let continuation = takeBatchContinuationLocked()
    let tasks = activeDownloads.values.map(\.task)
    activeDownloads.removeAll()
    taskBytesWritten.removeAll()
    continuationLock.unlock()

    for task in tasks {
      task.cancel()
    }
    continuation?.resume(throwing: error)
  }

  private func takeBatchContinuationLocked() -> CheckedContinuation<Void, Error>? {
    let continuation = batchContinuation
    batchContinuation = nil
    return continuation
  }

  private func withDownloadStateLock<T>(_ body: () -> T) -> T {
    continuationLock.lock()
    defer { continuationLock.unlock() }
    return body()
  }

  private func finish(success: Bool, error: Error?) {
    _executing = false
    _finished = true

    progressSubject.send(completion: .finished)

    if success {
      downloadSession.finishTasksAndInvalidate()
    } else {
      downloadSession.invalidateAndCancel()
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

  private func updateProgress(taskID: Int, totalBytesWritten: Int64) {
    guard totalBytes > 0 else { return }
    continuationLock.lock()
    taskBytesWritten[taskID] = totalBytesWritten
    let totalBytesDownloaded = bytesDownloadedSoFar + taskBytesWritten.values.reduce(0, +)
    continuationLock.unlock()
    let newProgress = Double(totalBytesDownloaded) / Double(totalBytes)
    progressSubject.send(min(newProgress, 1.0))
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
    updateProgress(taskID: downloadTask.taskIdentifier, totalBytesWritten: totalBytesWritten)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard
      let downloadTask = task as? URLSessionDownloadTask,
      let error
    else { return }

    let isCancelled = (error as? URLError)?.code == .cancelled || error is CancellationError
    if isCancelled {
      completeBatch(with: error)
    } else {
      AppLogger.download.error("Download attempt failed: \(error.localizedDescription)")
      retry(downloadTask, after: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    if let httpResponse = downloadTask.response as? HTTPURLResponse {
      guard (200...299).contains(httpResponse.statusCode) else {
        let statusDescription = HTTPURLResponse.localizedString(
          forStatusCode: httpResponse.statusCode
        ).capitalized
        AppLogger.download.error("Download failed with HTTP \(httpResponse.statusCode): \(statusDescription)")
        let error = URLError(
          .badServerResponse,
          userInfo: [NSLocalizedDescriptionKey: statusDescription]
        )
        retry(downloadTask, after: error)
        return
      }
    }

    do {
      try complete(downloadTask, at: location)
    } catch {
      retry(downloadTask, after: error)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor in
      let manager = DownloadManager.shared
      manager.backgroundCompletionHandler?()
      manager.backgroundCompletionHandler = nil
    }
  }
}

extension AudioTrack {
  var sanitizedExt: String {
    switch mimeType?.lowercased() {
    case "audio/mpeg": return ".mp3"
    case "audio/mp4", "audio/x-m4a": return ".m4a"
    case "audio/ogg": return ".ogg"
    case "audio/flac": return ".flac"
    case "audio/aac": return ".aac"
    case "audio/x-aiff": return ".aiff"
    case "audio/webm": return ".webm"
    case "audio/wav", "audio/x-wav": return ".wav"
    case "audio/x-caf": return ".caf"
    case "audio/opus": return ".opus"
    default: break
    }

    switch codec?.lowercased() {
    case "mp3": return ".mp3"
    case "aac", "alac": return ".m4a"
    case "opus": return ".opus"
    case "vorbis": return ".ogg"
    case "flac": return ".flac"
    case let codec where codec?.hasPrefix("pcm") == true: return ".wav"
    default: break
    }

    return metadata?.ext ?? ".mp3"
  }
}
