import API
import Combine
import Foundation
import Logging
import Models
import Network
import Pulse
import SwiftData
import UIKit

final class DownloadManager: NSObject, ObservableObject {
  static let shared = DownloadManager()

  nonisolated static let appGroupIdentifier = "group.me.jgrenier.audioBS"

  nonisolated static let sessionIdentifier = "me.jgrenier.AudioBS.download"

  nonisolated static let appGroupContainer: URL = {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
      fatalError("App group container '\(appGroupIdentifier)' not configured")
    }
    return url
  }()

  nonisolated static func serverDirectory(serverID: String) -> URL {
    appGroupContainer.appendingPathComponent(serverID)
  }

  nonisolated static func audiobookPath(serverID: String, bookID: String) -> String {
    "\(serverID)/audiobooks/\(bookID)"
  }

  nonisolated static func ebookPath(serverID: String, bookID: String) -> String {
    "\(serverID)/ebooks/\(bookID)"
  }

  nonisolated static func episodePath(serverID: String, podcastID: String, episodeID: String) -> String {
    "\(serverID)/episodes/\(podcastID)/\(episodeID)"
  }

  nonisolated static func audiobookDirectory(serverID: String, bookID: String) -> URL {
    appGroupContainer.appendingPathComponent(audiobookPath(serverID: serverID, bookID: bookID))
  }

  nonisolated static func ebookDirectory(serverID: String, bookID: String) -> URL {
    appGroupContainer.appendingPathComponent(ebookPath(serverID: serverID, bookID: bookID))
  }

  nonisolated static func episodeDirectory(serverID: String, podcastID: String, episodeID: String) -> URL {
    appGroupContainer.appendingPathComponent(
      episodePath(serverID: serverID, podcastID: podcastID, episodeID: episodeID)
    )
  }

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
  }

  struct DownloadFile {
    let request: URLRequest
    let expectedSize: Int64
    let relativePath: String
    let destination: URL
    var attempt: Int = 0
    var task: URLSessionDownloadTask?
  }

  final class ActiveDownload {
    let itemID: String
    let kind: DownloadRequest.Kind
    let podcastID: String?
    let priority: Float
    let totalBytes: Int64
    var files: [String: DownloadFile]
    var bytesWritten: [String: Int64] = [:]
    var bytesCompleted: Int64

    init(
      itemID: String,
      kind: DownloadRequest.Kind,
      podcastID: String?,
      priority: Float,
      files: [String: DownloadFile],
      bytesCompleted: Int64,
      totalBytes: Int64
    ) {
      self.itemID = itemID
      self.kind = kind
      self.podcastID = podcastID
      self.priority = priority
      self.files = files
      self.bytesCompleted = bytesCompleted
      self.totalBytes = totalBytes
    }

    var progress: Double {
      guard totalBytes > 0 else { return 0 }
      let downloaded = bytesCompleted + bytesWritten.values.reduce(0, +)
      return min(Double(downloaded) / Double(totalBytes), 1.0)
    }
  }

  private static let maxRetryAttempts = 3

  private var active: ActiveDownload?
  private var isPreparing = false
  private var lastProgressPublish = Date.distantPast

  @Published var downloadStates: [String: DownloadState] = [:]

  private var backgroundCompletionHandler: (() -> Void)?
  private var cancellables: Set<AnyCancellable> = []

  private let sessionDelegate = DownloadSessionDelegate()

  lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.timeoutIntervalForRequest = 300
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.httpMaximumConnectionsPerHost = 4
    return URLSession(
      configuration: config,
      delegate: URLSessionProxyDelegate(delegate: sessionDelegate),
      delegateQueue: nil
    )
  }()

  nonisolated static func itemID(fromRelativePath path: String) -> String? {
    let components = path.split(separator: "/").map(String.init)
    guard components.count >= 4 else { return nil }
    switch components[1] {
    case "audiobooks", "ebooks": return components[2]
    case "episodes" where components.count == 5: return components[3]
    default: return nil
    }
  }

  func reattachInFlightDownloads() async {
    guard active == nil else { return }

    let tasks = await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }

    guard active == nil, !isPreparing else { return }

    var byItem: [String: [URLSessionDownloadTask]] = [:]
    for task in tasks {
      guard
        let path = task.taskDescription,
        let itemID = Self.itemID(fromRelativePath: path)
      else { continue }
      byItem[itemID, default: []].append(task)
    }

    var candidates: [(request: DownloadRequest, tasks: [URLSessionDownloadTask])] = []
    for (itemID, itemTasks) in byItem {
      guard let request = try? DownloadRequest.fetch(itemID: itemID) else {
        AppLogger.download.info("Cancelling in-flight tasks with no request: \(itemID)")
        for task in itemTasks {
          task.cancel()
        }
        continue
      }
      candidates.append((request, itemTasks))
    }

    guard let candidate = candidates.min(by: { $0.request < $1.request }) else { return }

    for other in candidates where other.request.itemID != candidate.request.itemID {
      AppLogger.download.info("Cancelling untracked in-flight tasks for \(other.request.itemID)")
      for task in other.tasks {
        task.cancel()
      }
    }

    let request = candidate.request
    let itemID = request.itemID

    var files: [String: DownloadFile] = [:]
    var bytesWritten: [String: Int64] = [:]
    for task in candidate.tasks {
      guard let path = task.taskDescription, let originalRequest = task.originalRequest else { continue }
      files[path] = DownloadFile(
        request: originalRequest,
        expectedSize: task.countOfBytesExpectedToReceive,
        relativePath: path,
        destination: Self.appGroupContainer.appendingPathComponent(path),
        task: task
      )
      bytesWritten[path] = task.countOfBytesReceived
    }

    guard !files.isEmpty else { return }

    let download = ActiveDownload(
      itemID: itemID,
      kind: request.kind,
      podcastID: request.podcastID,
      priority: URLSessionTask.defaultPriority,
      files: files,
      bytesCompleted: downloadedBytes(itemID: itemID, kind: request.kind, podcastID: request.podcastID),
      totalBytes: request.size
    )
    download.bytesWritten = bytesWritten
    active = download
    downloadStates[itemID] = .downloading(progress: download.progress)

    AppLogger.download.info("Reattached \(files.count) in-flight file(s) for \(itemID)")
  }

  override init() {
    super.init()
    updateDownloadStates()

    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in self?.resumeOutstandingRequests() }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: NetworkMonitor.didChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.resumeOutstandingRequests() }
      .store(in: &cancellables)
  }

  func resumeOutstandingRequests() {
    guard NetworkMonitor.shared.interfaceType == .wifi else { return }
    startNextIfIdle()
  }

  private func directories(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String?
  ) -> [URL] {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else { return [] }

    switch kind {
    case .book:
      return [
        Self.audiobookDirectory(serverID: serverID, bookID: itemID),
        Self.ebookDirectory(serverID: serverID, bookID: itemID),
      ]
    case .ebook:
      return [Self.ebookDirectory(serverID: serverID, bookID: itemID)]
    case .episode:
      guard let podcastID else { return [] }
      return [Self.episodeDirectory(serverID: serverID, podcastID: podcastID, episodeID: itemID)]
    }
  }

  private func downloadedBytes(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String?
  ) -> Int64 {
    directories(itemID: itemID, kind: kind, podcastID: podcastID)
      .reduce(Int64(0)) { $0 + $1.directorySize }
  }

  func downloadedFraction(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String?,
    size: Int64
  ) -> Double {
    guard size > 0 else { return 0 }
    let bytes = downloadedBytes(itemID: itemID, kind: kind, podcastID: podcastID)
    return min(Double(bytes) / Double(size), 1.0)
  }

  func updateDownloadStates() {
    guard Audiobookshelf.shared.libraries.current != nil else { return }

    if let books = try? LocalBook.fetchAll() {
      for book in books {
        if case .downloading = downloadStates[book.bookID] { continue }
        downloadStates[book.bookID] = book.isDownloaded ? .downloaded : .notDownloaded
      }
    }

    if let episodes = try? LocalEpisode.fetchAll() {
      for episode in episodes {
        if case .downloading = downloadStates[episode.episodeID] { continue }
        downloadStates[episode.episodeID] = episode.isDownloaded ? .downloaded : .notDownloaded
      }
    }
  }

  private func persistedState(for id: String) -> DownloadState {
    if let book = try? LocalBook.fetch(bookID: id) {
      return book.isDownloaded ? .downloaded : .notDownloaded
    }
    if let episode = try? LocalEpisode.fetch(episodeID: id) {
      return episode.isDownloaded ? .downloaded : .notDownloaded
    }
    return .notDownloaded
  }

  func registerDownloadedFile(relativePath: String) {
    let components = relativePath.split(separator: "/").map(String.init)
    guard components.count >= 4 else { return }
    guard components[0] == Audiobookshelf.shared.authentication.server?.id else { return }

    switch components[1] {
    case "audiobooks":
      guard
        let book = try? LocalBook.fetch(bookID: components[2]),
        let index = Int(components[3].split(separator: ".").first ?? ""),
        let track = book.tracks.first(where: { $0.index == index }),
        track.relativePath == nil
      else { return }
      track.relativePath = URL(string: relativePath)
      try? book.save()

    case "ebooks":
      guard
        let book = try? LocalBook.fetch(bookID: components[2]),
        book.ebookFile == nil
      else { return }
      book.ebookFile = URL(string: relativePath)
      try? book.save()

    case "episodes" where components.count == 5:
      guard
        let episode = try? LocalEpisode.fetch(episodeID: components[3]),
        let track = episode.track,
        track.relativePath == nil
      else { return }
      track.relativePath = URL(string: relativePath)
      try? episode.save()

    default:
      break
    }
  }

  private func refreshStateIfIdle(for id: String) {
    reapRequestIfSatisfied(for: id)
    guard active?.itemID != id else { return }
    downloadStates[id] = persistedState(for: id)
  }

  private func reapRequestIfSatisfied(for itemID: String) {
    guard
      let request = try? DownloadRequest.fetch(itemID: itemID),
      isRequestSatisfied(itemID: itemID, kind: request.kind)
    else { return }
    try? request.delete()
  }

  func isDownloading(for bookID: String) -> Bool {
    active?.itemID == bookID
  }

  func startDownload(_ book: Book, kind: DownloadRequest.Kind = .book) {
    enqueue(
      itemID: book.id,
      kind: kind,
      title: book.title,
      coverURL: book.coverURL(),
      duration: book.duration,
      size: book.size ?? 0
    )
  }

  func startDownload(_ book: LocalBook, kind: DownloadRequest.Kind = .book) {
    enqueue(
      itemID: book.bookID,
      kind: kind,
      title: book.title,
      coverURL: book.coverURL(),
      duration: book.duration,
      size: book.tracks.reduce(0) { $0 + ($1.size ?? 0) }
    )
  }

  func startDownload(_ episode: PodcastEpisode, podcastID: String, coverURL: URL?) {
    enqueue(
      itemID: episode.id,
      kind: .episode,
      podcastID: podcastID,
      title: episode.title,
      coverURL: coverURL,
      duration: episode.duration ?? 0,
      size: episode.size ?? 0
    )
  }

  func startDownload(_ episode: LocalEpisode) {
    guard let podcastID = episode.podcast?.podcastID else { return }
    enqueue(
      itemID: episode.episodeID,
      kind: .episode,
      podcastID: podcastID,
      title: episode.title,
      coverURL: episode.coverURL(),
      duration: episode.duration,
      size: episode.track?.size ?? 0
    )
  }

  func resumeDownload(_ request: DownloadRequest) {
    enqueue(
      itemID: request.itemID,
      kind: request.kind,
      podcastID: request.podcastID,
      title: request.title,
      coverURL: request.coverURL,
      duration: request.duration,
      size: request.size
    )
  }

  private func enqueue(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String? = nil,
    title: String,
    coverURL: URL?,
    duration: TimeInterval,
    size: Int64
  ) {
    if kind == .episode, podcastID == nil { return }

    var kind = kind
    if let existing = try? DownloadRequest.fetch(itemID: itemID), existing.kind != kind {
      kind = .book
      existing.kind = .book
      try? existing.save()
    }

    guard active?.itemID != itemID else { return }

    if kind != .ebook, downloadStates[itemID] == .downloaded {
      reapRequestIfSatisfied(for: itemID)
      return
    }

    AppLogger.download.info("Queueing \(kind.rawValue) download for book: \(itemID)")

    try? DownloadRequest(
      itemID: itemID,
      kind: kind,
      podcastID: podcastID,
      title: title,
      coverURL: coverURL,
      duration: duration,
      size: size
    ).save()

    if let request = try? DownloadRequest.fetch(itemID: itemID), request.hasFailed {
      request.failureCount = 0
      try? request.save()
    }

    startNextIfIdle()
  }

  private func startNextIfIdle() {
    guard active == nil, !isPreparing else { return }

    let requests = (try? DownloadRequest.fetchAll()) ?? []
    let outstanding =
      requests
      .filter { !$0.hasFailed }
      .sorted()

    guard let request = outstanding.first else { return }

    let itemID = request.itemID
    let kind = request.kind
    let podcastID = request.podcastID

    isPreparing = true
    downloadStates[itemID] = .downloading(progress: 0)

    Task {
      do {
        let started = try await prepare(itemID: itemID, kind: kind, podcastID: podcastID)
        if !started {
          finish(itemID: itemID, kind: kind)
        }
      } catch {
        isPreparing = false
        AppLogger.download.error("Download failed for \(itemID): \(error.localizedDescription)")
        fail(itemID: itemID, error: error)
      }
    }
  }

  private func prepare(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String?
  ) async throws -> Bool {
    let plan: (files: [DownloadFile], totalBytes: Int64)
    switch kind {
    case .book, .ebook:
      plan = try await planBook(itemID: itemID, kind: kind)
    case .episode:
      guard let podcastID else { throw URLError(.badURL) }
      plan = try await planEpisode(episodeID: itemID, podcastID: podcastID)
    }

    guard await StorageManager.shared.canDownload(additionalBytes: plan.totalBytes) else {
      AppLogger.download.error("Storage limit reached for book: \(itemID)")
      Toast(error: "Storage limit reached").show()
      throw CancellationError()
    }

    let request = try? DownloadRequest.fetch(itemID: itemID)

    guard request != nil else {
      AppLogger.download.info("Download cancelled while preparing: \(itemID)")
      throw CancellationError()
    }

    var pending: [DownloadFile] = []
    var bytesCompleted: Int64 = 0
    for file in plan.files {
      if file.expectedSize > 0, diskSize(of: file.destination) == file.expectedSize {
        registerDownloadedFile(relativePath: file.relativePath)
        bytesCompleted += file.expectedSize
      } else {
        pending.append(file)
      }
    }

    guard !pending.isEmpty else {
      AppLogger.download.info("All files already present for book: \(itemID)")
      isPreparing = false
      return false
    }

    let isStreaming =
      PlayerManager.shared.current?.isPlaying == true
      && PlayerManager.shared.current?.downloadState == .notDownloaded
    let priority = isStreaming ? URLSessionTask.lowPriority : URLSessionTask.defaultPriority

    let download = ActiveDownload(
      itemID: itemID,
      kind: kind,
      podcastID: podcastID,
      priority: priority,
      files: Dictionary(uniqueKeysWithValues: pending.map { ($0.relativePath, $0) }),
      bytesCompleted: bytesCompleted,
      totalBytes: plan.totalBytes
    )
    active = download
    isPreparing = false

    AppLogger.download.info("Starting \(pending.count) download task(s) for book: \(itemID)")
    for file in pending {
      let task = makeTask(for: file, priority: priority)
      download.files[file.relativePath]?.task = task
      task.resume()
    }

    return true
  }

  private func makeTask(
    for file: DownloadFile,
    priority: Float,
    resumeData: Data? = nil
  ) -> URLSessionDownloadTask {
    let task: URLSessionDownloadTask
    if let resumeData {
      task = session.downloadTask(withResumeData: resumeData)
    } else {
      task = session.downloadTask(with: file.request)
    }
    task.taskDescription = file.relativePath
    task.countOfBytesClientExpectsToReceive = file.expectedSize > 0 ? file.expectedSize : 500_000_000
    task.priority = priority
    return task
  }

  fileprivate func progressed(relativePath: String, bytesWritten: Int64) {
    guard let download = active, download.files[relativePath] != nil else { return }
    download.bytesWritten[relativePath] = bytesWritten

    guard Date().timeIntervalSince(lastProgressPublish) >= 0.1 else { return }
    lastProgressPublish = Date()
    downloadStates[download.itemID] = .downloading(progress: download.progress)
  }

  fileprivate func fileFinished(relativePath: String, task: URLSessionDownloadTask) {
    registerDownloadedFile(relativePath: relativePath)

    guard let download = active, let file = download.files[relativePath], file.task === task else {
      if let itemID = Self.itemID(fromRelativePath: relativePath) {
        refreshStateIfIdle(for: itemID)
      }
      return
    }

    download.files.removeValue(forKey: relativePath)
    download.bytesWritten.removeValue(forKey: relativePath)
    download.bytesCompleted += diskSize(of: file.destination)

    guard download.files.isEmpty else {
      downloadStates[download.itemID] = .downloading(progress: download.progress)
      return
    }

    finish(itemID: download.itemID, kind: download.kind)
  }

  fileprivate func fileFailed(
    relativePath: String,
    task: URLSessionTask,
    error: Error,
    resumeData: Data?,
    retryable: Bool = true
  ) {
    guard let download = active, var file = download.files[relativePath], file.task === task else {
      if let itemID = Self.itemID(fromRelativePath: relativePath) {
        releaseOrphanedDownload(itemID: itemID)
      }
      return
    }

    let wasCancelled = (error as? URLError)?.code == .cancelled || error is CancellationError
    file.attempt += 1

    guard retryable, !wasCancelled, file.attempt < Self.maxRetryAttempts else {
      fail(itemID: download.itemID, error: error)
      return
    }

    download.files[relativePath] = file
    let delay = pow(2.0, Double(file.attempt))
    AppLogger.download.info(
      "Retry \(file.attempt)/\(Self.maxRetryAttempts - 1) in \(delay)s for \(relativePath)"
    )

    Task {
      try? await Task.sleep(for: .seconds(delay))
      guard active === download, download.files[relativePath] != nil else { return }
      let task = makeTask(for: file, priority: download.priority, resumeData: resumeData)
      download.files[relativePath]?.task = task
      task.resume()
    }
  }

  private func finish(itemID: String, kind: DownloadRequest.Kind) {
    active = nil

    let request = try? DownloadRequest.fetch(itemID: itemID)
    let currentKind = request?.kind ?? kind

    if isRequestSatisfied(itemID: itemID, kind: currentKind) {
      deleteRequest(for: itemID)
      Toast(success: "Download completed").show()
      AppLogger.download.info("Download completed for book: \(itemID)")
    } else if let request, currentKind == kind {
      request.failureCount += 1
      try? request.save()
      AppLogger.download.error("Download incomplete for book: \(itemID)")
    }

    downloadStates[itemID] = persistedState(for: itemID)
    startNextIfIdle()
  }

  private func fail(itemID: String, error: Error) {
    cancelActiveTasks(for: itemID)
    active = nil

    let isOffline = !NetworkMonitor.shared.isConnected
    let wasCancelled = (error as? URLError)?.code == .cancelled || error is CancellationError

    if !isOffline {
      if let request = try? DownloadRequest.fetch(itemID: itemID) {
        request.failureCount += 1
        try? request.save()
      }

      if !wasCancelled {
        Toast(error: "Download failed: \(error.localizedDescription)").show()
      }
    }

    downloadStates[itemID] = persistedState(for: itemID)

    guard !isOffline else {
      AppLogger.download.info("Offline, holding queue until connectivity returns")
      return
    }

    startNextIfIdle()
  }

  private func cancelActiveTasks(for itemID: String) {
    guard let download = active, download.itemID == itemID else { return }
    for file in download.files.values {
      file.task?.cancel()
    }
  }

  func saveEpisodeRecord(podcast: Podcast, podcastID: String, episodeID: String) {
    guard
      let apiEpisode = podcast.media.episodes?.first(where: { $0.id == episodeID }),
      let audioTrack = apiEpisode.audioTrack, audioTrack.ino != nil
    else { return }

    let ext = audioTrack.sanitizedExt
    let fileSize = audioTrack.metadata?.size ?? apiEpisode.size ?? 0

    try? LocalPodcast(from: podcast).save()
    guard let localPodcast = try? LocalPodcast.fetch(podcastID: podcastID) else { return }

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
        relativePath: nil
      ),
      chapters: (apiEpisode.chapters ?? []).map {
        Chapter(id: $0.id, start: $0.start, end: $0.end, title: $0.title)
      }
    )
    try? localEpisode.save()
  }

  func cancelDownload(for bookID: String) {
    let request = try? DownloadRequest.fetch(itemID: bookID)
    let isActive = active?.itemID == bookID

    guard request != nil || isActive else { return }

    AppLogger.download.info("Cancelling download for book: \(bookID)")

    let kind = isActive ? active?.kind : request?.kind
    let podcastID = isActive ? active?.podcastID : request?.podcastID

    cancelActiveTasks(for: bookID)
    if isActive {
      active = nil
    }

    deleteRequest(for: bookID)
    cancelSessionTasks(for: bookID)

    if let kind {
      cleanupPartialDownload(itemID: bookID, kind: kind, podcastID: podcastID)
    }

    downloadStates[bookID] = persistedState(for: bookID)
    startNextIfIdle()
  }

  private func cancelSessionTasks(for itemID: String) {
    Task {
      for task in await session.allTasks
      where task.taskDescription.flatMap(Self.itemID(fromRelativePath:)) == itemID {
        task.cancel()
      }
    }
  }

  private func cleanupPartialDownload(
    itemID: String,
    kind: DownloadRequest.Kind,
    podcastID: String?
  ) {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else { return }

    switch kind {
    case .book, .ebook:
      guard let book = try? LocalBook.fetch(bookID: itemID) else { return }

      let audioComplete = !book.tracks.isEmpty && book.tracks.allSatisfy { $0.relativePath != nil }

      if kind == .book, !audioComplete {
        try? FileManager.default.removeItem(
          at: Self.audiobookDirectory(serverID: serverID, bookID: itemID)
        )
        for track in book.tracks {
          track.relativePath = nil
        }
      }

      if book.ebookFile == nil {
        try? FileManager.default.removeItem(
          at: Self.ebookDirectory(serverID: serverID, bookID: itemID)
        )
      }

      if book.ebookFile == nil,
        book.tracks.allSatisfy({ $0.relativePath == nil }),
        PlayerManager.shared.current?.id != itemID
      {
        try? book.delete()
      } else {
        try? book.save()
      }

    case .episode:
      guard let podcastID else { return }
      guard let episode = try? LocalEpisode.fetch(episodeID: itemID) else { return }
      guard episode.track?.relativePath == nil else { return }

      try? FileManager.default.removeItem(
        at: Self.episodeDirectory(serverID: serverID, podcastID: podcastID, episodeID: itemID)
      )

      if PlayerManager.shared.current?.id != itemID {
        try? episode.delete()
      }
    }
  }

  fileprivate func releaseOrphanedDownload(itemID: String) {
    guard active?.itemID != itemID else { return }
    AppLogger.download.info("Releasing stalled download from a previous session: \(itemID)")
    downloadStates[itemID] = persistedState(for: itemID)
  }

  private func isRequestSatisfied(itemID: String, kind: DownloadRequest.Kind) -> Bool {
    switch kind {
    case .book:
      return (try? LocalBook.fetch(bookID: itemID))?.isDownloaded == true
    case .ebook:
      return (try? LocalBook.fetch(bookID: itemID))?.ebookFile != nil
    case .episode:
      return (try? LocalEpisode.fetch(episodeID: itemID))?.isDownloaded == true
    }
  }

  private func deleteRequest(for itemID: String) {
    guard let request = try? DownloadRequest.fetch(itemID: itemID) else { return }
    try? request.delete()
  }

  func handleBackgroundSessionEvents(identifier: String, completionHandler: @escaping () -> Void) {
    guard identifier == Self.sessionIdentifier else {
      completionHandler()
      return
    }

    backgroundCompletionHandler = completionHandler
    _ = session

    Task { await reattachInFlightDownloads() }
  }

  func finishBackgroundEvents() {
    backgroundCompletionHandler?()
    backgroundCompletionHandler = nil
  }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let relativePath = downloadTask.taskDescription else { return }
    Task { @MainActor in
      DownloadManager.shared.progressed(
        relativePath: relativePath,
        bytesWritten: totalBytesWritten
      )
    }
  }

  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, let relativePath = task.taskDescription else { return }

    AppLogger.download.error("Download attempt failed: \(error.localizedDescription)")
    let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

    Task { @MainActor in
      DownloadManager.shared.fileFailed(
        relativePath: relativePath,
        task: task,
        error: error,
        resumeData: resumeData
      )
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let relativePath = downloadTask.taskDescription, !relativePath.contains("..") else {
      AppLogger.download.warning("Discarding download with no destination")
      try? FileManager.default.removeItem(at: location)
      return
    }

    if let httpResponse = downloadTask.response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      try? FileManager.default.removeItem(at: location)

      let statusDescription = HTTPURLResponse.localizedString(
        forStatusCode: httpResponse.statusCode
      ).capitalized
      AppLogger.download.error("Download failed with HTTP \(httpResponse.statusCode): \(statusDescription)")

      let error = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: statusDescription])
      let retryable = httpResponse.statusCode >= 500 || httpResponse.statusCode == 429

      Task { @MainActor in
        DownloadManager.shared.fileFailed(
          relativePath: relativePath,
          task: downloadTask,
          error: error,
          resumeData: nil,
          retryable: retryable
        )
      }
      return
    }

    do {
      try store(location, at: relativePath)
    } catch {
      AppLogger.download.error("Failed to store \(relativePath): \(error.localizedDescription)")
      try? FileManager.default.removeItem(at: location)

      Task { @MainActor in
        DownloadManager.shared.fileFailed(
          relativePath: relativePath,
          task: downloadTask,
          error: error,
          resumeData: nil
        )
      }
      return
    }

    Task { @MainActor in
      DownloadManager.shared.fileFinished(relativePath: relativePath, task: downloadTask)
    }
  }

  private func store(_ location: URL, at relativePath: String) throws {
    let destination = DownloadManager.appGroupContainer.appendingPathComponent(relativePath)

    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: location, to: destination)
  }

  nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor in
      DownloadManager.shared.finishBackgroundEvents()
    }
  }
}

extension DownloadManager {
  private func removeDownloadedFiles(id: String, directories: [URL]) {
    cancelDownload(for: id)
    deleteRequest(for: id)

    for directory in directories {
      try? FileManager.default.removeItem(at: directory)
    }

    downloadStates[id] = .notDownloaded
  }

  func deleteDownload(for bookID: String) {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      AppLogger.download.error("No active server for deletion")
      Toast(error: "No active server").show()
      return
    }

    removeDownloadedFiles(
      id: bookID,
      directories: [
        Self.audiobookDirectory(serverID: serverID, bookID: bookID),
        Self.ebookDirectory(serverID: serverID, bookID: bookID),
      ]
    )

    if let book = try? LocalBook.fetch(bookID: bookID) {
      if PlayerManager.shared.current?.id == bookID {
        clearDownloadedPaths(of: book)
      } else {
        try? book.delete()
      }
    }

    AppLogger.download.info("Deleted download for book: \(bookID)")
  }

  func deleteEbookDownload(for bookID: String) {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      AppLogger.download.error("No active server for deletion")
      Toast(error: "No active server").show()
      return
    }

    cancelDownload(for: bookID)
    deleteRequest(for: bookID)
    try? FileManager.default.removeItem(at: Self.ebookDirectory(serverID: serverID, bookID: bookID))

    if let book = try? LocalBook.fetch(bookID: bookID) {
      book.ebookFile = nil
      try? book.save()
    }

    AppLogger.download.info("Deleted ebook download for book: \(bookID)")
  }

  func deleteEpisodeDownload(episodeID: String, podcastID: String) {
    guard let serverID = Audiobookshelf.shared.authentication.server?.id else {
      AppLogger.download.error("No active server for deletion")
      Toast(error: "No active server").show()
      return
    }

    removeDownloadedFiles(
      id: episodeID,
      directories: [Self.episodeDirectory(serverID: serverID, podcastID: podcastID, episodeID: episodeID)]
    )

    if let episode = try? LocalEpisode.fetch(episodeID: episodeID) {
      if PlayerManager.shared.current?.id == episodeID {
        episode.track?.relativePath = nil
        try? episode.save()
      } else {
        try? episode.delete()
      }
    }

    AppLogger.download.info("Deleted download for episode: \(episodeID)")
  }

  private func clearDownloadedPaths(of book: LocalBook) {
    for track in book.tracks {
      track.relativePath = nil
    }
    book.ebookFile = nil
    try? book.save()
  }

  func removeCompleted() {
    guard UserPreferences.shared.removeDownloadOnCompletion else { return }

    let currentPlayingID = PlayerManager.shared.current?.id

    for (id, state) in downloadStates {
      guard state == .downloaded, id != currentPlayingID else { continue }
      guard let progress = try? MediaProgress.fetch(bookID: id), progress.isFinished else { continue }

      if let episode = try? LocalEpisode.fetch(episodeID: id), let podcastID = episode.podcast?.podcastID {
        deleteEpisodeDownload(episodeID: id, podcastID: podcastID)
      } else {
        deleteDownload(for: id)
      }
    }
  }

  func deleteAllServerData() async {
    if let itemID = active?.itemID {
      cancelDownload(for: itemID)
    }

    for task in await session.allTasks {
      task.cancel()
    }

    for request in (try? DownloadRequest.fetchAll()) ?? [] {
      try? request.delete()
    }

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

      for book in (try? LocalBook.fetchAll()) ?? [] {
        clearDownloadedPaths(of: book)
      }
      for episode in (try? LocalEpisode.fetchAll()) ?? [] {
        episode.track?.relativePath = nil
        try? episode.save()
      }

      downloadStates = downloadStates.mapValues { _ in .notDownloaded }

      AppLogger.download.info("Deleted all server data")
    } catch {
      AppLogger.download.error(
        "Failed to delete all server data: \(error.localizedDescription)"
      )
    }
  }
}

extension DownloadManager {
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

  private func prepareDownloadDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

    var parent = url.deletingLastPathComponent()
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? parent.setResourceValues(values)
  }

  func diskSize(of url: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? Int64) ?? 0
  }

  private func makeFile(
    url: URL,
    relativePath: String,
    expectedSize: Int64,
    credentials: Credentials
  ) -> DownloadFile {
    DownloadFile(
      request: authorizedRequest(url: url, credentials: credentials),
      expectedSize: expectedSize,
      relativePath: relativePath,
      destination: Self.appGroupContainer.appendingPathComponent(relativePath)
    )
  }

  func planBook(
    itemID: String,
    kind: DownloadRequest.Kind
  ) async throws -> (files: [DownloadFile], totalBytes: Int64) {
    let book = try await Audiobookshelf.shared.books.fetch(id: itemID)
    let context = try await currentServerContext()

    let serverHasAudio = book.mediaType.contains(.audiobook) && !(book.tracks ?? []).isEmpty
    let serverHasEbook = book.mediaType.contains(.ebook)

    let wantsAudio = kind == .book && serverHasAudio
    let wantsEbook = (kind == .book || kind == .ebook) && serverHasEbook

    guard wantsAudio || wantsEbook else {
      AppLogger.download.error("Nothing to download for book \(itemID)")
      throw URLError(.badURL)
    }

    try? LocalBook(from: book).save()

    var files: [DownloadFile] = []
    var totalBytes: Int64 = 0

    if wantsEbook, let ebookURL = book.ebookURL {
      let ext: String
      if let ebookFileExt = book.media.ebookFile?.metadata.ext {
        ext = ebookFileExt
      } else {
        let pathExt = ebookURL.pathExtension
        ext = pathExt.isEmpty ? ".epub" : ".\(pathExt)"
      }

      let directoryPath = DownloadManager.ebookPath(serverID: context.serverID, bookID: itemID)
      try prepareDownloadDirectory(
        DownloadManager.ebookDirectory(serverID: context.serverID, bookID: itemID)
      )

      let expectedSize = book.media.ebookFile?.metadata.size ?? 0
      files.append(
        makeFile(
          url: ebookURL,
          relativePath: "\(directoryPath)/\(itemID)\(ext)",
          expectedSize: expectedSize,
          credentials: context.credentials
        )
      )
      totalBytes += expectedSize
    }

    if wantsAudio {
      let directoryPath = DownloadManager.audiobookPath(serverID: context.serverID, bookID: itemID)
      try prepareDownloadDirectory(
        DownloadManager.audiobookDirectory(serverID: context.serverID, bookID: itemID)
      )

      for apiTrack in book.tracks ?? [] {
        guard let ino = apiTrack.ino else {
          AppLogger.download.error("Track \(apiTrack.index) has no file id for book: \(itemID)")
          throw URLError(.badServerResponse)
        }

        let expectedSize = apiTrack.metadata?.size ?? 0
        let trackURL = context.serverURL.appendingPathComponent(
          "api/items/\(itemID)/file/\(ino)/download"
        )

        files.append(
          makeFile(
            url: trackURL,
            relativePath: "\(directoryPath)/\(apiTrack.index)\(apiTrack.sanitizedExt)",
            expectedSize: expectedSize,
            credentials: context.credentials
          )
        )
        totalBytes += expectedSize
      }
    }

    guard !files.isEmpty else {
      AppLogger.download.error("Planned no files for book: \(itemID)")
      throw URLError(.badURL)
    }

    AppLogger.download.info("Planned \(files.count) file(s), \(totalBytes.formattedByteSize) for book: \(itemID)")
    return (files, totalBytes)
  }

  func planEpisode(
    episodeID: String,
    podcastID: String
  ) async throws -> (files: [DownloadFile], totalBytes: Int64) {
    let podcast = try await Audiobookshelf.shared.podcasts.fetch(id: podcastID)
    let context = try await currentServerContext()

    saveEpisodeRecord(podcast: podcast, podcastID: podcastID, episodeID: episodeID)

    guard let apiEpisode = podcast.media.episodes?.first(where: { $0.id == episodeID }) else {
      AppLogger.download.error("Episode not found: \(episodeID)")
      throw URLError(.badURL)
    }

    guard let audioTrack = apiEpisode.audioTrack, let ino = audioTrack.ino else {
      AppLogger.download.error("No audio track for episode: \(episodeID)")
      throw URLError(.badURL)
    }

    let directoryPath = DownloadManager.episodePath(
      serverID: context.serverID,
      podcastID: podcastID,
      episodeID: episodeID
    )
    try prepareDownloadDirectory(
      DownloadManager.episodeDirectory(
        serverID: context.serverID,
        podcastID: podcastID,
        episodeID: episodeID
      )
    )

    let expectedSize = audioTrack.metadata?.size ?? apiEpisode.size ?? 0
    let trackURL = context.serverURL.appendingPathComponent(
      "api/items/\(podcastID)/file/\(ino)/download"
    )

    let file = makeFile(
      url: trackURL,
      relativePath: "\(directoryPath)/0\(audioTrack.sanitizedExt)",
      expectedSize: expectedSize,
      credentials: context.credentials
    )

    AppLogger.download.info("Planned \(expectedSize.formattedByteSize) for episode: \(episodeID)")
    return ([file], expectedSize)
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
