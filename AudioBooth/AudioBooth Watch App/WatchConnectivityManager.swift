import Combine
import Foundation
import OSLog
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  @Published var continueListeningBooks: [WatchBook] = []
  @Published var progress: [String: Double] = [:]
  @Published var hasCurrentBook: Bool = false
  @Published var playbackRate: Float = 1.0

  private var session: WCSession?
  private var cancellables = Set<AnyCancellable>()

  private enum Keys {
    static let continueListeningBooks = "continue_listening_books"
    static let progress = "progress"
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
      session?.activate()
    }
  }

  private func setupObservers() {
    LocalBookStorage.shared.$books
      .dropFirst()
      .map { books in books.filter { $0.isDownloaded }.map { $0.id } }
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] downloadedBookIDs in
        self?.sendDownloadedBookIDs(downloadedBookIDs)
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
  }

  private func persistBooks(_ books: [WatchBook]) {
    guard let data = try? JSONEncoder().encode(books) else { return }
    UserDefaults.standard.set(data, forKey: Keys.continueListeningBooks)
    UserDefaults.standard.set(progress, forKey: Keys.progress)
  }

  func sendCommand(_ command: String) {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot send command - session not reachable")
      return
    }

    let message = ["command": command]
    session.sendMessage(message, replyHandler: nil) { error in
      AppLogger.watchConnectivity.error("Failed to send command to iOS: \(error)")
    }
  }

  func play() {
    sendCommand("play")
  }

  func pause() {
    sendCommand("pause")
  }

  func skipForward() {
    sendCommand("skipForward")
  }

  func skipBackward() {
    sendCommand("skipBackward")
  }

  func playOnIPhone(bookID: String) {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot play on iPhone - session not reachable")
      return
    }

    let message: [String: Any] = [
      "command": "play",
      "bookID": bookID,
    ]
    session.sendMessage(message, replyHandler: nil) { error in
      AppLogger.watchConnectivity.error("Failed to send play command to iOS: \(error)")
    }
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

  func sendDownloadedBookIDs(_ ids: [String]) {
    guard let session = session, session.isReachable else {
      AppLogger.watchConnectivity.warning("Cannot send downloaded book IDs - session not reachable")
      return
    }

    let message: [String: Any] = [
      "command": "syncDownloadedBooks",
      "bookIDs": ids,
    ]
    session.sendMessage(message, replyHandler: nil) { error in
      AppLogger.watchConnectivity.error("Failed to send downloaded book IDs to iOS: \(error)")
    }

    AppLogger.watchConnectivity.info("Sent \(ids.count) downloaded book IDs to iPhone")
  }

  func reportProgress(bookID: String, sessionID: String, currentTime: Double, timeListened: Double, duration: Double) {
    guard let session = session, session.isReachable else { return }

    let message: [String: Any] = [
      "command": "reportProgress",
      "bookID": bookID,
      "sessionID": sessionID,
      "currentTime": currentTime,
      "timeListened": timeListened,
      "duration": duration,
    ]

    session.sendMessage(message, replyHandler: nil, errorHandler: nil)
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

        guard let id = response["id"] as? String,
          let title = response["title"] as? String,
          let duration = response["duration"] as? Double,
          let tracksData = response["tracks"] as? [[String: Any]],
          let chaptersData = response["chapters"] as? [[String: Any]]
        else {
          if let error = response["error"] as? String {
            AppLogger.watchConnectivity.error("Failed to start session: \(error)")
          }
          completion(nil)
          return
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

        let book = WatchBook(
          id: id,
          sessionID: sessionID,
          title: title,
          authorName: response["authorName"] as? String,
          coverURL: coverURL,
          duration: duration,
          chapters: chapters,
          tracks: tracks,
          currentTime: self.progress[id, default: 0]
        )

        AppLogger.watchConnectivity.info("Started session for \(id)")
        completion(book)
      },
      errorHandler: { error in
        AppLogger.watchConnectivity.error("sendMessage error: \(error.localizedDescription)")
        completion(nil)
      }
    )
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
        }

        if session.isReachable {
          let downloadedBookIDs = LocalBookStorage.shared.books
            .filter { $0.isDownloaded }
            .map { $0.id }
          sendDownloadedBookIDs(downloadedBookIDs)
        }
      }
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in
      handleContext(applicationContext)
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in
      handleMessage(message)
    }
  }

  private func handleContext(_ context: [String: Any]) {
    let continueListeningData = context["continueListening"] as? [[String: Any]] ?? []
    handleContinueListening(continueListeningData)

    let progressData = context["progress"] as? [String: Double] ?? [:]
    handleProgress(progressData)

    hasCurrentBook = context["hasCurrentBook"] as? Bool ?? false
    playbackRate = context["playbackRate"] as? Float ?? 1.0
  }

  private func handleMessage(_ message: [String: Any]) {
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
  }

  private func handleProgress(_ data: [String: Double]) {
    var updatedBooks = continueListeningBooks

    for (bookID, currentTime) in data {
      progress[bookID] = currentTime

      if let index = updatedBooks.firstIndex(where: { $0.id == bookID }) {
        updatedBooks[index].currentTime = currentTime
      }

      LocalBookStorage.shared.updateProgress(for: bookID, currentTime: currentTime)
    }

    continueListeningBooks = updatedBooks
    persistBooks(continueListeningBooks)
  }

}
