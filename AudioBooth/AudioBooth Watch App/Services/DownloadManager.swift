import Combine
import Foundation
import OSLog

final class DownloadManager: NSObject, ObservableObject {
  static let shared = DownloadManager()

  enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case paused(progress: Double)
    case downloaded
  }

  private struct TaskInfo {
    let bookID: String
    let index: Int
    let ext: String

    init?(_ task: URLSessionTask) {
      let parts = task.taskDescription?.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false) ?? []
      guard parts.count == 3, let index = Int(parts[1]) else { return nil }
      self.bookID = String(parts[0])
      self.index = index
      self.ext = String(parts[2])
    }
  }

  private static let sessionIdentifier = "me.jgrenier.AudioBS.watch.downloads"
  private static let legacySessionPrefix = "me.jgrenier.AudioBS.watch.download."
  private static let migrationKey = "downloads_migrated_to_shared_session"
  private static let autoResumeInterval: TimeInterval = 300
  private static let freshPayloadInterval: TimeInterval = 600

  private let localStorage = LocalBookStorage.shared
  private let connectivityManager = WatchConnectivityManager.shared

  @Published private(set) var currentProgress: [String: Double] = [:]
  @Published private(set) var activeBookIDs: Set<String> = []

  private var enqueueTokens: [String: UUID] = [:]
  private var pendingArmedCallbacks: [String: [() -> Void]] = [:]
  private var inFlight: [String: Set<Int>] = [:]
  private var trackedTaskIDs: Set<Int> = []
  private var completedTaskIDs: Set<Int> = []
  private var bytesWritten: [String: [Int: Int64]] = [:]
  private var resumedTaskIDs: Set<Int> = []
  private var retriedTracks: Set<String> = []
  private var pendingCancellations: [String: Task<Void, Never>] = [:]
  private var lastAutoAttempt: [String: Date] = [:]
  private var backgroundCompletions: [() -> Void] = []
  private var hasDeliveredBackgroundEvents = false
  private var pendingRetries = 0

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.timeoutIntervalForRequest = 60
    config.allowsCellularAccess = true
    config.waitsForConnectivity = true
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true
    config.httpMaximumConnectionsPerHost = 1
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }()

  func start() {
    migrateIfNeeded()
    cleanupOrphanedDownloads()
    _ = session
  }

  func downloadState(for bookID: String) -> DownloadState {
    let stored = storedBook(bookID)
    if let stored, stored.isDownloaded {
      return .downloaded
    }
    if activeBookIDs.contains(bookID) {
      return .downloading(progress: currentProgress[bookID] ?? stored?.downloadProgress ?? 0)
    }
    if let stored {
      return .paused(progress: stored.downloadProgress)
    }
    return .notDownloaded
  }

  func startDownload(
    for book: WatchBook,
    downloadTracks: [WatchTrack]? = nil,
    payloadSentAt: Date? = nil,
    refreshOnly: Bool = false,
    onArmed: (() -> Void)? = nil
  ) {
    let armed = onArmed.map(makeOnce)

    if storedBook(book.id) == nil {
      guard !refreshOnly else {
        armed?()
        return
      }
      localStorage.saveBook(
        WatchBook(
          id: book.id,
          title: book.title,
          authorName: book.authorName,
          coverURL: book.coverURL,
          duration: book.duration,
          chapters: book.chapters,
          currentTime: book.currentTime
        )
      )
    }

    if let downloadTracks {
      localStorage.updateBook(book.id) { stored in
        stored.tracks = Self.merge(downloadTracks, into: stored.tracks, bookID: book.id)
      }
    }

    if let armed {
      pendingArmedCallbacks[book.id, default: []].append(armed)
    }

    guard enqueueTokens[book.id] == nil else { return }

    let token = UUID()
    enqueueTokens[book.id] = token
    updateActiveBookIDs()

    let skipRefetch = payloadSentAt.map { Date().timeIntervalSince($0) < Self.freshPayloadInterval } ?? false
    Task {
      await enqueue(bookID: book.id, token: token, skipRefetch: skipRefetch)
    }
  }

  func applicationDidBecomeActive() {
    hasDeliveredBackgroundEvents = false
    resumeIncompleteDownloads()
  }

  func resumeIncompleteDownloads(bypassThrottle: Bool = false) {
    let now = Date()
    for book in localStorage.books where !book.isDownloaded && !activeBookIDs.contains(book.id) {
      if !bypassThrottle, let last = lastAutoAttempt[book.id],
        now.timeIntervalSince(last) < Self.autoResumeInterval
      {
        continue
      }
      lastAutoAttempt[book.id] = now
      startDownload(for: book)
    }
  }

  func reconnectBackgroundSession(withIdentifier identifier: String, completion: @escaping () -> Void) {
    if identifier == Self.sessionIdentifier {
      _ = session
      backgroundCompletions.append(makeOnce(completion))
      completeBackgroundEventsIfPossible()
      return
    }

    if identifier.hasPrefix(Self.legacySessionPrefix) {
      AppLogger.download.info("Discarding legacy background session: \(identifier)")
      let config = URLSessionConfiguration.background(withIdentifier: identifier)
      URLSession(configuration: config).invalidateAndCancel()
    }
    completion()
  }

  private func enqueue(bookID: String, token: UUID, skipRefetch: Bool) async {
    defer {
      if enqueueTokens[bookID] == token {
        enqueueTokens.removeValue(forKey: bookID)
        updateActiveBookIDs()
        updateProgress(for: bookID)
      }
      for callback in pendingArmedCallbacks.removeValue(forKey: bookID) ?? [] {
        callback()
      }
    }

    clearRetries(for: bookID)
    await pendingCancellations[bookID]?.value

    if !skipRefetch {
      let refreshed = await refreshTracks(for: bookID)
      if !refreshed {
        AppLogger.download.warning("Could not refresh download info for \(bookID), using stored tracks")
      }
    }

    let existingTasks = await session.allTasks.filter { task in
      (task.state == .running || task.state == .suspended)
        && !completedTaskIDs.contains(task.taskIdentifier)
        && TaskInfo(task)?.bookID == bookID
    }

    guard enqueueTokens[bookID] == token, let book = storedBook(bookID) else { return }

    guard !book.tracks.isEmpty else {
      AppLogger.download.error("No tracks available to download for \(bookID)")
      deleteDownload(for: bookID)
      return
    }

    let busyIndices = Set(existingTasks.compactMap { TaskInfo($0)?.index }).union(inFlight[bookID] ?? [])
    trackedTaskIDs.formUnion(existingTasks.map(\.taskIdentifier))

    for track in book.tracks.sorted(by: { $0.index < $1.index }) {
      guard let ext = track.ext, !ext.isEmpty else {
        AppLogger.download.error("Track \(track.index) missing file extension, cannot download")
        continue
      }

      let relativePath = Self.relativePath(bookID: bookID, index: track.index, ext: ext)
      if FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(relativePath).path) {
        if track.relativePath != relativePath {
          setTrackPath(relativePath, bookID: bookID, index: track.index)
        }
        continue
      }

      if busyIndices.contains(track.index) {
        inFlight[bookID, default: []].insert(track.index)
        continue
      }

      createTask(bookID: bookID, track: track)
    }

    AppLogger.download.info("Queued \(self.inFlight[bookID]?.count ?? 0) tracks for \(bookID)")
  }

  @discardableResult
  private func refreshTracks(for bookID: String) async -> Bool {
    guard let info = await connectivityManager.startSession(bookID: bookID, forDownload: true) else {
      return false
    }

    guard storedBook(bookID) != nil else { return false }

    localStorage.updateBook(bookID) { stored in
      stored = WatchBook(
        id: stored.id,
        title: info.title,
        authorName: info.authorName,
        coverURL: info.coverURL ?? stored.coverURL,
        duration: info.duration,
        chapters: info.chapters,
        tracks: Self.merge(info.tracks, into: stored.tracks, bookID: bookID),
        currentTime: stored.currentTime
      )
    }
    return true
  }

  private func createTask(bookID: String, track: WatchTrack, fresh: Bool = false) {
    guard let ext = track.ext, !ext.isEmpty else { return }

    let task: URLSessionDownloadTask
    if !fresh, let resumeData = loadResumeData(bookID: bookID, index: track.index) {
      AppLogger.download.info("Resuming track \(track.index) for \(bookID)")
      task = session.downloadTask(withResumeData: resumeData)
      resumedTaskIDs.insert(task.taskIdentifier)
    } else {
      guard let url = track.url else {
        AppLogger.download.error("Track \(track.index) missing download URL")
        return
      }
      var request = URLRequest(url: url)
      for (key, value) in connectivityManager.customHeaders {
        request.setValue(value, forHTTPHeaderField: key)
      }
      task = session.downloadTask(with: request)
    }

    task.taskDescription = "\(bookID)|\(track.index)|\(ext)"
    task.countOfBytesClientExpectsToReceive = Int64(track.size ?? 500_000_000)
    trackedTaskIDs.insert(task.taskIdentifier)
    inFlight[bookID, default: []].insert(track.index)
    task.resume()
  }

  private func retry(_ info: TaskInfo, refreshingURLs: Bool) {
    inFlight[info.bookID, default: []].insert(info.index)
    pendingRetries += 1

    Task {
      defer {
        pendingRetries -= 1
        completeBackgroundEventsIfPossible()
      }

      if refreshingURLs {
        await refreshTracks(for: info.bookID)
      }

      inFlight[info.bookID]?.remove(info.index)
      if let track = storedBook(info.bookID)?.tracks.first(where: { $0.index == info.index }) {
        createTask(bookID: info.bookID, track: track, fresh: true)
      }
      finishIfIdle(info.bookID)
    }
  }

  private func finishIfIdle(_ bookID: String) {
    if inFlight[bookID]?.isEmpty ?? true {
      inFlight.removeValue(forKey: bookID)
      bytesWritten.removeValue(forKey: bookID)
      currentProgress.removeValue(forKey: bookID)
      updateActiveBookIDs()
    } else {
      updateProgress(for: bookID)
    }
  }

  private func updateActiveBookIDs() {
    let active = Set(enqueueTokens.keys).union(inFlight.filter { !$0.value.isEmpty }.keys)
    if active != activeBookIDs {
      activeBookIDs = active
    }
  }

  private func updateProgress(for bookID: String) {
    guard activeBookIDs.contains(bookID), let book = storedBook(bookID) else { return }

    let totalBytes = book.tracks.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
    guard totalBytes > 0 else { return }

    let completedBytes = book.tracks.filter { $0.relativePath != nil }.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
    let pendingIndices = Set(book.tracks.filter { $0.relativePath == nil }.map(\.index))
    let partialBytes = (bytesWritten[bookID] ?? [:])
      .filter { pendingIndices.contains($0.key) }
      .reduce(Int64(0)) { $0 + $1.value }

    let progress = min(1, Double(completedBytes + partialBytes) / Double(totalBytes))
    if let current = currentProgress[bookID], abs(current - progress) < 0.01 { return }
    currentProgress[bookID] = progress
  }

  private func setTrackPath(_ relativePath: String, bookID: String, index: Int) {
    localStorage.updateBook(bookID) { stored in
      if let trackIndex = stored.tracks.firstIndex(where: { $0.index == index }) {
        stored.tracks[trackIndex].relativePath = relativePath
      }
    }
  }

  private func clearRetries(for bookID: String) {
    retriedTracks = retriedTracks.filter { !$0.hasPrefix("\(bookID)|") }
  }

  private func storedBook(_ bookID: String) -> WatchBook? {
    localStorage.books.first { $0.id == bookID }
  }

  private func makeOnce(_ callback: @escaping () -> Void) -> () -> Void {
    var hasCalled = false
    let once = {
      guard !hasCalled else { return }
      hasCalled = true
      callback()
    }
    Task {
      try? await Task.sleep(for: .seconds(20))
      once()
    }
    return once
  }

  private func migrateIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
    UserDefaults.standard.set(true, forKey: Self.migrationKey)

    for book in localStorage.books where !book.isDownloaded {
      let config = URLSessionConfiguration.background(withIdentifier: Self.legacySessionPrefix + book.id)
      URLSession(configuration: config).invalidateAndCancel()
      deleteDownload(for: book.id)
    }
  }

  private static func relativePath(bookID: String, index: Int, ext: String) -> String {
    "audiobooks/\(bookID)/\(index)\(ext)"
  }

  private static func merge(_ newTracks: [WatchTrack], into existing: [WatchTrack], bookID: String) -> [WatchTrack] {
    newTracks.map { track in
      var track = track
      let expectedPath = track.ext.map { relativePath(bookID: bookID, index: track.index, ext: $0) }
      let existingPath = existing.first { $0.index == track.index }?.relativePath
      track.relativePath = existingPath == expectedPath ? existingPath : nil
      return track
    }
  }
}

extension DownloadManager {
  private func resumeDataURL(bookID: String, index: Int) -> URL {
    URL.documentsDirectory.appendingPathComponent("audiobooks/\(bookID)/.resume-\(index).dat")
  }

  private func loadResumeData(bookID: String, index: Int) -> Data? {
    try? Data(contentsOf: resumeDataURL(bookID: bookID, index: index))
  }

  private func saveResumeData(_ data: Data, bookID: String, index: Int) {
    let url = resumeDataURL(bookID: bookID, index: index)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  private func clearResumeData(bookID: String, index: Int) {
    try? FileManager.default.removeItem(at: resumeDataURL(bookID: bookID, index: index))
  }
}

extension DownloadManager {
  func deleteDownload(for bookID: String) {
    enqueueTokens.removeValue(forKey: bookID)
    for callback in pendingArmedCallbacks.removeValue(forKey: bookID) ?? [] {
      callback()
    }
    inFlight.removeValue(forKey: bookID)
    bytesWritten.removeValue(forKey: bookID)
    currentProgress.removeValue(forKey: bookID)
    clearRetries(for: bookID)
    updateActiveBookIDs()

    let bookDirectory = URL.documentsDirectory.appendingPathComponent("audiobooks").appendingPathComponent(bookID)

    do {
      if FileManager.default.fileExists(atPath: bookDirectory.path) {
        try FileManager.default.removeItem(at: bookDirectory)
      }
    } catch {
      AppLogger.download.error("Failed to delete download: \(error.localizedDescription)")
    }

    localStorage.deleteBook(bookID)

    let previousCancellation = pendingCancellations[bookID]
    pendingCancellations[bookID] = Task {
      await previousCancellation?.value
      for task in await session.allTasks where TaskInfo(task)?.bookID == bookID {
        trackedTaskIDs.remove(task.taskIdentifier)
        task.cancel()
      }
    }
  }

  func cleanupOrphanedDownloads() {
    let audiobooksDirectory = URL.documentsDirectory.appendingPathComponent("audiobooks")

    guard FileManager.default.fileExists(atPath: audiobooksDirectory.path) else {
      AppLogger.download.debug("Audiobooks directory does not exist, nothing to cleanup")
      return
    }

    do {
      let downloadDirectories = try FileManager.default.contentsOfDirectory(
        at: audiobooksDirectory,
        includingPropertiesForKeys: [.isDirectoryKey]
      )

      let localBookIDs = Set(localStorage.books.map { $0.id })

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

extension DownloadManager: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard trackedTaskIDs.contains(downloadTask.taskIdentifier), let info = TaskInfo(downloadTask) else { return }
    self.bytesWritten[info.bookID, default: [:]][info.index] = totalBytesWritten
    updateProgress(for: info.bookID)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let info = TaskInfo(downloadTask), storedBook(info.bookID) != nil else { return }

    if let httpResponse = downloadTask.response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      return
    }

    let relativePath = Self.relativePath(bookID: info.bookID, index: info.index, ext: info.ext)
    let destination = URL.documentsDirectory.appendingPathComponent(relativePath)

    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: location, to: destination)
    } catch {
      AppLogger.download.error("Failed to save track \(info.index) for \(info.bookID): \(error)")
      return
    }

    clearResumeData(bookID: info.bookID, index: info.index)
    retriedTracks.remove("\(info.bookID)|\(info.index)")
    setTrackPath(relativePath, bookID: info.bookID, index: info.index)

    if storedBook(info.bookID)?.isDownloaded == true {
      AppLogger.download.info("Download completed for \(info.bookID)")
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let wasResumed = resumedTaskIDs.remove(task.taskIdentifier) != nil

    let isTracked = trackedTaskIDs.remove(task.taskIdentifier) != nil
    completedTaskIDs.insert(task.taskIdentifier)

    guard let info = TaskInfo(task), storedBook(info.bookID) != nil else { return }

    let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    if let resumeData {
      saveResumeData(resumeData, bookID: info.bookID, index: info.index)
    }

    guard isTracked else { return }

    inFlight[info.bookID]?.remove(info.index)
    bytesWritten[info.bookID]?.removeValue(forKey: info.index)
    defer { finishIfIdle(info.bookID) }

    let statusCode = (task.response as? HTTPURLResponse)?.statusCode
    let isHTTPError = statusCode.map { !(200...299).contains($0) } ?? false

    guard error != nil || isHTTPError else { return }

    if (error as? URLError)?.code == .cancelled {
      return
    }

    AppLogger.download.warning(
      "Track \(info.index) for \(info.bookID) failed (status: \(statusCode ?? 0)): \(error?.localizedDescription ?? "")"
    )

    let retryKey = "\(info.bookID)|\(info.index)"
    guard !retriedTracks.contains(retryKey) else { return }

    if statusCode == 401 || statusCode == 403 {
      retriedTracks.insert(retryKey)
      clearResumeData(bookID: info.bookID, index: info.index)
      retry(info, refreshingURLs: true)
    } else if wasResumed && (resumeData == nil || isHTTPError) {
      retriedTracks.insert(retryKey)
      clearResumeData(bookID: info.bookID, index: info.index)
      retry(info, refreshingURLs: false)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    hasDeliveredBackgroundEvents = true
    completeBackgroundEventsIfPossible()
  }

  private func completeBackgroundEventsIfPossible() {
    guard hasDeliveredBackgroundEvents, pendingRetries == 0, !backgroundCompletions.isEmpty else { return }

    hasDeliveredBackgroundEvents = false
    let completions = backgroundCompletions
    backgroundCompletions.removeAll()
    for completion in completions {
      completion()
    }
  }
}
