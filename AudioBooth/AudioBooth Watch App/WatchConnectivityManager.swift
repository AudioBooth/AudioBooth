import Combine
import Foundation
import OSLog
import WatchConnectivity
import WatchKit
import WidgetKit

struct DownloadStatus: Equatable {
  let downloaded: [String]
  let queued: [String]

  static var current: DownloadStatus {
    let books = LocalBookStorage.shared.books
    return DownloadStatus(
      downloaded: books.filter { $0.isDownloaded }.map { $0.id },
      queued: books.filter { !$0.isDownloaded }.map { $0.id }
    )
  }
}

struct WatchHomeSection: Identifiable, Hashable {
  let id: String
  let name: String
  let count: Int
}

final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  @Published var continueListeningBooks: [WatchBook] = []
  @Published var progress: [String: Double] = [:]
  private(set) var progressUpdatedAt: [String: Double] = [:]
  @Published var hasCurrentBook: Bool = false
  @Published var playbackRate: Float = 1.0
  @Published var homeSections: [WatchHomeSection] = []
  private var chapterProgress: Double?
  private var currentBook: WatchBook?

  var customHeaders: [String: String] {
    get {
      UserDefaults.standard.dictionary(forKey: Keys.customHeaders) as? [String: String] ?? [:]
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.customHeaders)
    }
  }

  var skipForwardInterval: Double {
    get {
      let value = UserDefaults.standard.double(forKey: Keys.skipForwardInterval)
      return value > 0 ? value : 30
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.skipForwardInterval)
    }
  }

  var skipBackwardInterval: Double {
    get {
      let value = UserDefaults.standard.double(forKey: Keys.skipBackwardInterval)
      return value > 0 ? value : 30
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.skipBackwardInterval)
    }
  }

  private var session: WCSession?
  private var cancellables = Set<AnyCancellable>()
  private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
  private var pendingDownloadRequests = 0
  private var sessionObservations: [NSKeyValueObservation] = []

  private enum Keys {
    static let continueListeningBooks = "continue_listening_books"
    static let progress = "progress"
    static let progressUpdatedAt = "progress_updated_at"
    static let customHeaders = "custom_headers"
    static let skipForwardInterval = "skip_forward_interval"
    static let skipBackwardInterval = "skip_backward_interval"
  }

  var isReachable: Bool {
    session?.isReachable ?? false
  }

  private override init() {
    super.init()

    loadPersistedState()
    setupObservers()

    if WCSession.isSupported() {
      session = WCSession.default
      session?.delegate = self
      observeSessionState()
      session?.activate()
    }
  }

  private func setupObservers() {
    LocalBookStorage.shared.$books
      .dropFirst()
      .map { books in
        DownloadStatus(
          downloaded: books.filter { $0.isDownloaded }.map { $0.id },
          queued: books.filter { !$0.isDownloaded }.map { $0.id }
        )
      }
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        self?.sendDownloadStatus(status)
      }
      .store(in: &cancellables)
  }

  private func loadPersistedState() {
    if let data = UserDefaults.standard.data(forKey: Keys.continueListeningBooks),
      let books = try? JSONDecoder().decode([WatchBook].self, from: data)
    {
      continueListeningBooks = books
      AppLogger.watchConnectivity.info("Loaded \(books.count) persisted books")
    }

    if let progressData = UserDefaults.standard.dictionary(forKey: Keys.progress)
      as? [String: Double]
    {
      progress = progressData
    }

    if let updatedAtData = UserDefaults.standard.dictionary(forKey: Keys.progressUpdatedAt)
      as? [String: Double]
    {
      progressUpdatedAt = updatedAtData
    }
  }

  private func persistBooks(_ books: [WatchBook]) {
    guard let data = try? JSONEncoder().encode(books) else { return }
    UserDefaults.standard.set(data, forKey: Keys.continueListeningBooks)
    persistProgress()
  }

  private func persistProgress() {
    UserDefaults.standard.set(progress, forKey: Keys.progress)
    UserDefaults.standard.set(progressUpdatedAt, forKey: Keys.progressUpdatedAt)
  }

  func recordLocalProgress(bookID: String, currentTime: Double) {
    progress[bookID] = currentTime
    progressUpdatedAt[bookID] = Date().timeIntervalSince1970
    persistProgress()
    LocalBookStorage.shared.updateProgress(for: bookID, currentTime: currentTime)
  }

  func changePlaybackRate(_ rate: Float) {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot change playback rate - session not reachable")
      return
    }

    let message: [String: Any] = [
      "command": "changePlaybackRate",
      "rate": rate,
    ]
    session.sendMessage(message, replyHandler: nil) { error in
      AppLogger.watchConnectivity.error("Failed to send playback rate command to iOS: \(error)")
    }
  }

  func playOnPhone(bookID: String, currentTime: Double) {
    guard let session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot play on iPhone - session not reachable")
      return
    }

    let message: [String: Any] = [
      "command": "play",
      "bookID": bookID,
      "currentTime": currentTime,
    ]
    session.sendMessage(message, replyHandler: nil) { error in
      AppLogger.watchConnectivity.error("Failed to send play command to iOS: \(error)")
    }
  }

  func refreshContinueListening() async {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot refresh - session not reachable")
      return
    }

    await withCheckedContinuation { continuation in
      let message: [String: Any] = ["command": "refreshContinueListening"]
      session.sendMessage(
        message,
        replyHandler: { _ in
          continuation.resume()
        }
      ) { error in
        AppLogger.watchConnectivity.error("Failed to refresh continue listening: \(error)")
        continuation.resume()
      }
    }
  }

  func fetchSectionBooks(sectionID: String) async -> [WatchBook]? {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot fetch section - session not reachable")
      return nil
    }

    return await withCheckedContinuation { continuation in
      let message: [String: Any] = [
        "command": "fetchSectionBooks",
        "sectionID": sectionID,
      ]
      session.sendMessage(
        message,
        replyHandler: { response in
          if let error = response["error"] as? String {
            AppLogger.watchConnectivity.error("Failed to fetch section books: \(error)")
            continuation.resume(returning: nil)
            return
          }
          guard let booksData = response["books"] as? [[String: Any]] else {
            continuation.resume(returning: nil)
            return
          }
          let books = booksData.compactMap { WatchBook(dictionary: $0) }
          continuation.resume(returning: books)
        },
        errorHandler: { error in
          AppLogger.watchConnectivity.error("fetchSectionBooks error: \(error)")
          continuation.resume(returning: nil)
        }
      )
    }
  }

  func sendDownloadStatus(_ status: DownloadStatus = .current) {
    guard let session, session.activationState == .activated else { return }

    for transfer in session.outstandingUserInfoTransfers
    where transfer.userInfo["command"] as? String == "syncDownloadedBooks" {
      transfer.cancel()
    }

    session.transferUserInfo([
      "command": "syncDownloadedBooks",
      "bookIDs": status.downloaded,
      "queuedBookIDs": status.queued,
    ])

    AppLogger.watchConnectivity.info(
      "Sent \(status.downloaded.count) downloaded and \(status.queued.count) queued book IDs to iPhone"
    )
  }

  func handleBackgroundTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
    backgroundTasks.append(task)
    completeBackgroundTasksIfNeeded()

    Task { [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard let self, let index = backgroundTasks.firstIndex(where: { $0 === task }) else { return }
      backgroundTasks.remove(at: index)
      task.setTaskCompletedWithSnapshot(false)
    }
  }

  private func observeSessionState() {
    guard let session else { return }

    let onChange: () -> Void = { [weak self] in
      Task { @MainActor in
        self?.completeBackgroundTasksIfNeeded()
      }
    }

    sessionObservations = [
      session.observe(\.hasContentPending) { _, _ in onChange() },
      session.observe(\.activationState) { _, _ in onChange() },
    ]
  }

  private func completeBackgroundTasksIfNeeded() {
    guard !backgroundTasks.isEmpty,
      let session,
      session.activationState == .activated,
      !session.hasContentPending,
      pendingDownloadRequests == 0
    else { return }

    for task in backgroundTasks {
      task.setTaskCompletedWithSnapshot(false)
    }
    backgroundTasks.removeAll()
  }

  func reportProgress(bookID: String, sessionID: String?, currentTime: Double, timeListened: Double, duration: Double) {
    recordLocalProgress(bookID: bookID, currentTime: currentTime)

    guard let session, session.isReachable, let sessionID, !sessionID.isEmpty else {
      recordLocalSession(bookID: bookID, currentTime: currentTime, timeListened: timeListened, duration: duration)
      return
    }

    let message: [String: Any] = [
      "command": "reportProgress",
      "bookID": bookID,
      "sessionID": sessionID,
      "currentTime": currentTime,
      "timeListened": timeListened,
      "duration": duration,
    ]

    session.sendMessage(message, replyHandler: nil) { _ in
      Task { @MainActor in
        self.recordLocalSession(
          bookID: bookID,
          currentTime: currentTime,
          timeListened: timeListened,
          duration: duration
        )
      }
    }
  }

  private func recordLocalSession(bookID: String, currentTime: Double, timeListened: Double, duration: Double) {
    if let session, session.activationState == .activated {
      pruneSyncedLocalSessions(session.receivedApplicationContext)
    }

    WatchLocalSessionStore.shared.record(
      bookID: bookID,
      currentTime: currentTime,
      timeListened: timeListened,
      duration: duration
    )

    flushLocalSessions()
  }

  func flushLocalSessions() {
    guard let session, session.activationState == .activated else { return }

    let localSessions = WatchLocalSessionStore.shared.sessions
    guard !localSessions.isEmpty else { return }

    let payload: [[String: Any]] = localSessions.map { localSession in
      [
        "id": localSession.id,
        "bookID": localSession.bookID,
        "duration": localSession.duration,
        "startTime": localSession.startTime,
        "currentTime": localSession.currentTime,
        "timeListening": localSession.timeListening,
        "startedAt": localSession.startedAt.timeIntervalSince1970,
        "updatedAt": localSession.updatedAt.timeIntervalSince1970,
      ]
    }

    let message: [String: Any] = [
      "command": "syncLocalSessions",
      "sessions": payload,
    ]

    AppLogger.watchConnectivity.info("Flushing \(localSessions.count) local sessions to iPhone")

    for transfer in session.outstandingUserInfoTransfers
    where transfer.userInfo["command"] as? String == "syncLocalSessions" {
      transfer.cancel()
    }
    session.transferUserInfo(message)

    guard session.isReachable else { return }

    session.sendMessage(
      message,
      replyHandler: { response in
        if let error = response["error"] as? String {
          AppLogger.watchConnectivity.error("Failed to sync local sessions: \(error)")
        }
      },
      errorHandler: { error in
        AppLogger.watchConnectivity.error("Failed to send local sessions: \(error)")
      }
    )
  }

  private func pruneSyncedLocalSessions(_ context: [String: Any]) {
    guard let synced = context["syncedLocalSessions"] as? [String: Double] else { return }
    WatchLocalSessionStore.shared.remove(synced: synced, idleFor: 3600)
  }

  func startSession(bookID: String, forDownload: Bool = false) async -> WatchBook? {
    await withCheckedContinuation { continuation in
      startSessionWithCallback(bookID: bookID, forDownload: forDownload) { book in
        continuation.resume(returning: book)
      }
    }
  }

  private func startSessionWithCallback(
    bookID: String,
    forDownload: Bool,
    completion: @escaping (WatchBook?) -> Void
  ) {
    AppLogger.watchConnectivity.info(
      "startSession called for \(bookID), forDownload=\(forDownload)"
    )

    guard let session = session else {
      AppLogger.watchConnectivity.error("Cannot start session - no WCSession instance")
      completion(nil)
      return
    }

    AppLogger.watchConnectivity.info(
      "Session state - isReachable: \(session.isReachable), activationState: \(session.activationState.rawValue)"
    )

    guard session.isReachable else {
      AppLogger.watchConnectivity.error("Cannot start session - session not reachable")
      completion(nil)
      return
    }

    AppLogger.watchConnectivity.info("Sending startSession message to iOS...")

    let message: [String: Any] = [
      "command": "startSession",
      "bookID": bookID,
      "forDownload": forDownload,
    ]

    session.sendMessage(
      message,
      replyHandler: { response in
        AppLogger.watchConnectivity.info("Received reply from iOS")

        guard let book = self.makeBook(from: response) else {
          if let error = response["error"] as? String {
            AppLogger.watchConnectivity.error("Failed to start session: \(error)")
          }
          completion(nil)
          return
        }

        AppLogger.watchConnectivity.info("Started session for \(book.id)")
        completion(book)
      },
      errorHandler: { error in
        AppLogger.watchConnectivity.error("sendMessage error: \(error.localizedDescription)")
        completion(nil)
      }
    )
  }

  private func makeBook(from response: [String: Any]) -> WatchBook? {
    guard let id = response["id"] as? String,
      let title = response["title"] as? String,
      let duration = response["duration"] as? Double,
      let tracksData = response["tracks"] as? [[String: Any]],
      let chaptersData = response["chapters"] as? [[String: Any]]
    else {
      return nil
    }

    let tracks = tracksData.compactMap { dict -> WatchTrack? in
      guard let index = dict["index"] as? Int,
        let trackDuration = dict["duration"] as? Double
      else { return nil }
      let url = (dict["url"] as? String).flatMap { URL(string: $0) }
      return WatchTrack(
        index: index,
        duration: trackDuration,
        size: dict["size"] as? Int64,
        ext: dict["ext"] as? String,
        url: url,
        relativePath: nil
      )
    }

    let chapters = chaptersData.compactMap { dict -> WatchChapter? in
      guard let chapterID = dict["id"] as? Int,
        let chapterTitle = dict["title"] as? String,
        let start = dict["start"] as? Double,
        let end = dict["end"] as? Double
      else { return nil }
      return WatchChapter(id: chapterID, title: chapterTitle, start: start, end: end)
    }

    let coverURL = (response["coverURL"] as? String).flatMap { URL(string: $0) }
    let sessionID = response["sessionID"] as? String

    return WatchBook(
      id: id,
      sessionID: sessionID,
      title: title,
      authorName: response["authorName"] as? String,
      coverURL: coverURL,
      duration: duration,
      chapters: chapters,
      tracks: tracks,
      currentTime: progress[id, default: 0]
    )
  }

  private func handleDownloadRequest(_ userInfo: [String: Any]) {
    guard let payload = userInfo["book"] as? [String: Any], let book = makeBook(from: payload) else {
      AppLogger.watchConnectivity.error("Received invalid download request from iPhone")
      return
    }

    let sentAt = (userInfo["sentAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
    let refreshOnly = userInfo["refreshOnly"] as? Bool ?? false

    AppLogger.watchConnectivity.info("Received download request for \(book.id), refreshOnly=\(refreshOnly)")

    pendingDownloadRequests += 1
    DownloadManager.shared.startDownload(
      for: book,
      downloadTracks: book.tracks,
      payloadSentAt: sentAt,
      refreshOnly: refreshOnly,
      onArmed: { [weak self] in
        guard let self else { return }
        pendingDownloadRequests -= 1
        completeBackgroundTasksIfNeeded()
      }
    )

    if !refreshOnly {
      sendDownloadStatus()
    }
  }
}

extension WatchConnectivityManager: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      AppLogger.watchConnectivity.error("Watch session activation failed: \(error)")
    } else {
      AppLogger.watchConnectivity.info(
        "Watch session activated with state: \(activationState.rawValue)"
      )

      if activationState == .activated {
        let context = session.receivedApplicationContext
        Task { @MainActor in
          handleContext(context)
          flushLocalSessions()
          sendDownloadStatus()
          completeBackgroundTasksIfNeeded()
        }
      }
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    guard session.isReachable else { return }
    Task { @MainActor in
      flushLocalSessions()
      DownloadManager.shared.resumeIncompleteDownloads(bypassThrottle: true)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in
      handleContext(applicationContext)
      completeBackgroundTasksIfNeeded()
    }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    Task { @MainActor in
      if userInfo["command"] as? String == "downloadBook" {
        handleDownloadRequest(userInfo)
      }
      completeBackgroundTasksIfNeeded()
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in
      handleMessage(message)
    }
  }

  private func handleContext(_ context: [String: Any]) {
    pruneSyncedLocalSessions(context)

    hasCurrentBook = context["hasCurrentBook"] as? Bool ?? false
    playbackRate = context["playbackRate"] as? Float ?? 1.0
    chapterProgress = context["chapterProgress"] as? Double
    currentBook = (context["currentBook"] as? [String: Any]).flatMap { WatchBook(dictionary: $0) }

    let continueListeningData = context["continueListening"] as? [[String: Any]] ?? []
    handleContinueListening(continueListeningData)

    let progressData = context["progress"] as? [String: Double] ?? [:]
    let updatedAtData = context["progressUpdatedAt"] as? [String: Double] ?? [:]
    handleProgress(progressData, updatedAt: updatedAtData)

    let homeSectionsData = context["homeSections"] as? [[String: Any]] ?? []
    homeSections = homeSectionsData.compactMap { dict in
      guard let id = dict["id"] as? String,
        let name = dict["name"] as? String,
        let count = dict["count"] as? Int
      else { return nil }
      return WatchHomeSection(id: id, name: name, count: count)
    }

    if let headers = context["customHeaders"] as? [String: String] {
      customHeaders = headers
    }

    if let forward = context["skipForwardInterval"] as? Double {
      skipForwardInterval = forward
    }

    if let backward = context["skipBackwardInterval"] as? Double {
      skipBackwardInterval = backward
    }
  }

  private func handleMessage(_ message: [String: Any]) {
    if message["command"] as? String == "downloadBook" {
      handleDownloadRequest(message)
      return
    }

    if let progressData = message["progress"] as? [String: Double] {
      handleProgress(progressData)
    }
  }

  private func handleContinueListening(_ data: [[String: Any]]) {
    let books = data.compactMap { dict -> WatchBook? in
      let currentTime = progress[dict["id"] as? String ?? ""] ?? 0
      return WatchBook(dictionary: dict, currentTime: currentTime)
    }

    continueListeningBooks = books
    persistBooks(books)
    updateComplication()
  }

  private func handleProgress(_ data: [String: Double], updatedAt: [String: Double] = [:]) {
    var updatedBooks = continueListeningBooks

    for (bookID, currentTime) in data {
      if let remoteUpdatedAt = updatedAt[bookID] {
        let localUpdatedAt = progressUpdatedAt[bookID] ?? 0
        guard remoteUpdatedAt > localUpdatedAt else { continue }
        progressUpdatedAt[bookID] = remoteUpdatedAt
      } else {
        let localTime = progress[bookID] ?? 0
        guard currentTime > localTime else { continue }
      }

      progress[bookID] = currentTime

      if let index = updatedBooks.firstIndex(where: { $0.id == bookID }) {
        updatedBooks[index].currentTime = currentTime
      }

      LocalBookStorage.shared.updateProgress(for: bookID, currentTime: currentTime)
    }

    continueListeningBooks = updatedBooks
    persistBooks(continueListeningBooks)
    updateComplication()
  }

  func updateComplication() {
    if WatchComplicationStorage.load()?.isPlaying == true {
      return
    }

    if var book = currentBook ?? continueListeningBooks.first {
      book.currentTime = progress[book.id] ?? book.currentTime
      let state = WatchComplicationState(
        bookTitle: book.title,
        progress: book.progress,
        chapterProgress: chapterProgress,
        currentTime: book.currentTime,
        duration: book.duration,
        isPlaying: false
      )
      WatchComplicationStorage.save(state)
    } else {
      WatchComplicationStorage.clear()
    }
    WidgetCenter.shared.reloadAllTimelines()
  }

}
