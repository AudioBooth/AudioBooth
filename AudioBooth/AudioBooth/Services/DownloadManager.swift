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
    case episode(podcastID: String, episodeID: String)
  }

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
  }

  struct DownloadInfo {
    let title: String
    let details: String?
    let coverURL: URL?
    let startedAt: Date
  }

  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.name = "me.jgrenier.AudioBS.downloadQueue"
    return queue
  }()

  private var activeOperations: [String: DownloadOperation] = [:]
  private var progressTasks: [String: Task<Void, Never>] = [:]
  @Published var downloadStates: [String: DownloadState] = [:]
  @Published var downloadInfos: [String: DownloadInfo] = [:]

  var backgroundCompletionHandler: (() -> Void)?

  override init() {
    super.init()
    updateDownloadStates()
  }

  func updateDownloadStates() {
    guard Audiobookshelf.shared.isAuthenticated else { return }

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
    type: DownloadType = .audiobook,
    info: DownloadInfo? = nil,
  ) {
    guard activeOperations[bookID] == nil else {
      return
    }

    AppLogger.download.info("Starting \(type) download for book: \(bookID)")
    let operation = DownloadOperation(bookID: bookID, type: type)
    activeOperations[bookID] = operation

    Task { @MainActor [weak self] in
      self?.downloadStates[bookID] = .downloading(progress: 0)
      if let info {
        self?.downloadInfos[bookID] = info
      }
    }

    let progressTask = Task { @MainActor [weak self] in
      for await progress in operation.progress {
        guard !Task.isCancelled else { break }
        self?.downloadStates[bookID] = .downloading(progress: progress)
      }
    }
    progressTasks[bookID] = progressTask

    operation.completionBlock = { [weak self] in
      Task { @MainActor in
        self?.progressTasks[bookID]?.cancel()
        self?.progressTasks.removeValue(forKey: bookID)
        self?.activeOperations.removeValue(forKey: bookID)
        self?.downloadInfos.removeValue(forKey: bookID)

        if operation.isFinished && !operation.isCancelled {
          AppLogger.download.info("Download completed successfully for book: \(bookID)")
          self?.downloadStates[bookID] = .downloaded
        } else {
          AppLogger.download.info("Download cancelled or failed for book: \(bookID)")
          self?.downloadStates[bookID] = .notDownloaded
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
        AppLogger.download.error("Failed to access app group container for deletion")
        Toast(error: "Failed to access app group container").show()
        return
      }

      let serverDirectory = appGroupURL.appendingPathComponent(serverID)
      let audiobookDirectory = serverDirectory.appendingPathComponent("audiobooks").appendingPathComponent(bookID)
      let ebookDirectory = serverDirectory.appendingPathComponent("ebooks").appendingPathComponent(bookID)

      try? FileManager.default.removeItem(at: audiobookDirectory)
      try? FileManager.default.removeItem(at: ebookDirectory)

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
      guard
        let appGroupURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
        ),
        let serverID = Audiobookshelf.shared.authentication.server?.id
      else {
        AppLogger.download.error("Failed to access app group container for deletion")
        Toast(error: "Failed to access app group container").show()
        return
      }

      let serverDirectory = appGroupURL.appendingPathComponent(serverID)
      let episodeDirectory =
        serverDirectory
        .appendingPathComponent("episodes")
        .appendingPathComponent(podcastID)
        .appendingPathComponent(episodeID)

      try? FileManager.default.removeItem(at: episodeDirectory)

      if let episode = try? LocalEpisode.fetch(episodeID: episodeID) {
        try? episode.delete()
      }

      Task { @MainActor in
        downloadStates[episodeID] = .notDownloaded
      }

      AppLogger.download.info("Deleted download for episode: \(episodeID)")
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

  private var apiBook: Book?
  private var totalBytes: Int64 = 0
  private var bytesDownloadedSoFar: Int64 = 0

  private var currentTrack: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<Void, Error>?
  private var trackDestination: URL?

  private lazy var downloadSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "me.jgrenier.AudioBS.download.\(bookID)"
    )
    config.timeoutIntervalForRequest = 120
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
    AppLogger.download.info("Cancelling download for book: \(bookID)")
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

    let bookDirectory: URL
    switch type {
    case .audiobook:
      bookDirectory = appGroupURL.appendingPathComponent(serverID)
        .appendingPathComponent("audiobooks").appendingPathComponent(bookID)
    case .ebook:
      bookDirectory = appGroupURL.appendingPathComponent(serverID)
        .appendingPathComponent("ebooks").appendingPathComponent(bookID)
    case .episode(let podcastID, let episodeID):
      bookDirectory = appGroupURL.appendingPathComponent(serverID)
        .appendingPathComponent("episodes").appendingPathComponent(podcastID)
        .appendingPathComponent(episodeID)
    }

    try? FileManager.default.removeItem(at: bookDirectory)
  }

  private func executeDownload() async {
    do {
      switch type {
      case .audiobook:
        try await executeAudiobookDownload()
      case .ebook:
        try await executeEbookDownload()
      case .episode(let podcastID, let episodeID):
        try await executeEpisodeDownload(podcastID: podcastID, episodeID: episodeID)
      }
      finish(success: true, error: nil)
    } catch {
      AppLogger.download.error("Download failed for book \(bookID): \(error.localizedDescription)")
      finish(success: false, error: error)
    }
  }

  private func executeAudiobookDownload() async throws {
    let book = try await audiobookshelf.books.fetch(id: bookID)

    guard !isCancelled else {
      throw CancellationError()
    }

    self.apiBook = book
    self.totalBytes = (book.tracks ?? []).reduce(0) { $0 + ($1.metadata?.size ?? 0) }
    let trackCount = book.tracks?.count ?? 0
    AppLogger.download.info("Downloading audiobook: \(trackCount) tracks, \(totalBytes.formattedByteSize)")

    try await downloadTracks()

    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      throw URLError(.userAuthenticationRequired)
    }

    let localBook = LocalBook(from: book)
    for track in localBook.tracks {
      guard let ext = track.ext else { continue }
      track.relativePath = URL(string: "\(serverID)/audiobooks/\(bookID)/\(track.index)\(ext)")
    }
    try? localBook.save()
  }

  private func executeEbookDownload() async throws {
    let book = try await audiobookshelf.books.fetch(id: bookID)

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
    try await downloadEbook(from: ebookURL, ext: ext)

    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      throw URLError(.userAuthenticationRequired)
    }

    let localBook = LocalBook(from: book)
    localBook.ebookFile = URL(string: "\(serverID)/ebooks/\(bookID)/\(bookID)\(ext)")
    try? localBook.save()
  }

  private func executeEpisodeDownload(podcastID: String, episodeID: String) async throws {
    let podcast = try await audiobookshelf.podcasts.fetch(id: podcastID)

    guard !isCancelled else {
      throw CancellationError()
    }

    guard let apiEpisode = podcast.media.episodes?.first(where: { $0.id == episodeID }) else {
      AppLogger.download.error("Episode not found: \(episodeID)")
      throw URLError(.badURL)
    }

    guard let audioTrack = apiEpisode.audioTrack else {
      AppLogger.download.error("No audio track for episode: \(episodeID)")
      throw URLError(.badURL)
    }

    let fileSize = audioTrack.metadata?.size ?? apiEpisode.size ?? 0
    self.totalBytes = fileSize

    AppLogger.download.info("Downloading episode: \(apiEpisode.title), \(fileSize.formattedByteSize)")

    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      throw URLError(.fileDoesNotExist)
    }

    guard
      let serverID = Audiobookshelf.shared.authentication.server?.id,
      let serverURL = Audiobookshelf.shared.authentication.serverURL,
      let credentials = try? await Audiobookshelf.shared.authentication.server?.freshToken
    else {
      throw URLError(.userAuthenticationRequired)
    }

    let serverDirectory = appGroupURL.appendingPathComponent(serverID)
    var episodesDirectory = serverDirectory.appendingPathComponent("episodes")
    let episodeDirectory =
      episodesDirectory
      .appendingPathComponent(podcastID)
      .appendingPathComponent(episodeID)

    if FileManager.default.fileExists(atPath: episodeDirectory.path) {
      try? FileManager.default.removeItem(at: episodeDirectory)
    }

    try FileManager.default.createDirectory(at: episodeDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? episodesDirectory.setResourceValues(resourceValues)

    let ext = audioTrack.metadata?.ext ?? ".mp3"
    let trackURL = serverURL.appendingPathComponent("api/items/\(podcastID)/file/\(audioTrack.ino)/download")
    let trackFile = episodeDirectory.appendingPathComponent("0\(ext)")

    var request = URLRequest(url: trackURL)
    request.setValue(credentials.bearer, forHTTPHeaderField: "Authorization")

    if let customHeaders = Audiobookshelf.shared.authentication.server?.customHeaders {
      for (key, value) in customHeaders {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    try await withCheckedThrowingContinuation { continuation in
      let downloadTask = downloadSession.downloadTask(with: request)
      downloadTask.countOfBytesClientExpectsToReceive = fileSize > 0 ? fileSize : 500_000_000

      self.currentTrack = downloadTask
      self.continuation = continuation
      self.trackDestination = trackFile

      downloadTask.resume()
    }

    progressContinuation.yield(1.0)

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
        relativePath: URL(string: "\(serverID)/episodes/\(podcastID)/\(episodeID)/0\(ext)")
      ),
      chapters: (apiEpisode.chapters ?? []).map {
        Chapter(id: $0.id, start: $0.start, end: $0.end, title: $0.title)
      }
    )
    try? localEpisode.save()
  }

  private func downloadTracks() async throws {
    guard let apiBook else { throw URLError(.unknown) }

    let apiTracks = apiBook.tracks ?? []
    guard !apiTracks.isEmpty else {
      AppLogger.download.error("No tracks found for audiobook: \(bookID)")
      throw URLError(.badURL)
    }

    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      AppLogger.download.error("Failed to access app group container")
      throw URLError(.fileDoesNotExist)
    }

    guard
      let serverID = Audiobookshelf.shared.authentication.server?.id,
      let serverURL = Audiobookshelf.shared.authentication.serverURL,
      let credentials = try? await Audiobookshelf.shared.authentication.server?.freshToken
    else {
      AppLogger.download.error("Missing authentication credentials")
      throw URLError(.userAuthenticationRequired)
    }

    let serverDirectory = appGroupURL.appendingPathComponent(serverID)
    var audiobooksDirectory = serverDirectory.appendingPathComponent("audiobooks")
    let bookDirectory = audiobooksDirectory.appendingPathComponent(bookID)

    if FileManager.default.fileExists(atPath: bookDirectory.path) {
      try? FileManager.default.removeItem(at: bookDirectory)
    }

    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? audiobooksDirectory.setResourceValues(resourceValues)

    for apiTrack in apiTracks {
      guard !isCancelled else { throw CancellationError() }

      guard
        let ext = apiTrack.metadata?.ext,
        let ino = apiTrack.ino
      else {
        AppLogger.download.error("Invalid track metadata for track \(apiTrack.index)")
        throw URLError(.badURL)
      }

      let trackURL = serverURL.appendingPathComponent("api/items/\(bookID)/file/\(ino)/download")

      let trackFile = bookDirectory.appendingPathComponent("\(apiTrack.index)\(ext)")

      var request = URLRequest(url: trackURL)

      request.setValue(credentials.bearer, forHTTPHeaderField: "Authorization")

      if let customHeaders = Audiobookshelf.shared.authentication.server?.customHeaders {
        for (key, value) in customHeaders {
          request.setValue(value, forHTTPHeaderField: key)
        }
      }

      try await withCheckedThrowingContinuation { continuation in
        let downloadTask = downloadSession.downloadTask(with: request)
        downloadTask.countOfBytesClientExpectsToReceive = Int64(
          apiTrack.metadata?.size ?? 500_000_000
        )

        self.currentTrack = downloadTask
        self.continuation = continuation
        self.trackDestination = trackFile

        downloadTask.resume()
      }

      if let size = apiTrack.metadata?.size {
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
      AppLogger.download.error("Failed to access app group container")
      throw URLError(.fileDoesNotExist)
    }

    guard
      let serverID = Audiobookshelf.shared.authentication.server?.id,
      let credentials = try? await Audiobookshelf.shared.authentication.server?.freshToken
    else {
      AppLogger.download.error("Missing server ID for authentication")
      throw URLError(.userAuthenticationRequired)
    }

    let serverDirectory = appGroupURL.appendingPathComponent(serverID)
    var ebooksDirectory = serverDirectory.appendingPathComponent("ebooks")
    let bookDirectory = ebooksDirectory.appendingPathComponent(bookID)

    if FileManager.default.fileExists(atPath: bookDirectory.path) {
      try? FileManager.default.removeItem(at: bookDirectory)
    }

    try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? ebooksDirectory.setResourceValues(resourceValues)

    let ebookFile = bookDirectory.appendingPathComponent("\(bookID)\(ext)")

    var request = URLRequest(url: ebookURL)

    request.setValue(credentials.bearer, forHTTPHeaderField: "Authorization")

    if let customHeaders = Audiobookshelf.shared.authentication.server?.customHeaders {
      for (key, value) in customHeaders {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    try await withCheckedThrowingContinuation { continuation in
      let downloadTask = downloadSession.downloadTask(with: request)
      downloadTask.countOfBytesClientExpectsToReceive = 50_000_000

      self.currentTrack = downloadTask
      self.continuation = continuation
      self.trackDestination = ebookFile

      downloadTask.resume()
    }

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
        continuation?.resume(throwing: error)
        return
      }
    }

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
