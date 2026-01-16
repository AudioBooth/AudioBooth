import API
import Combine
import Foundation
import Logging
import Models
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  private var session: WCSession?
  private var context: [String: Any] = [:]

  private enum Keys {
    static let watchDownloadedBookIDs = "watch_downloaded_book_ids"
  }

  var watchDownloadedBookIDs: [String] {
    get { UserDefaults.standard.stringArray(forKey: Keys.watchDownloadedBookIDs) ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: Keys.watchDownloadedBookIDs) }
  }

  private override init() {
    super.init()

    if WCSession.isSupported() {
      session = WCSession.default
      session?.delegate = self
      session?.activate()
    }
  }

  static var watchDeviceID: String {
    SessionService.deviceID + "-watch"
  }

  func syncProgress(_ bookID: String) {
    guard let current = try? MediaProgress.fetch(bookID: bookID) else { return }

    var progress = context["progress"] as? [String: Double] ?? [:]
    progress[bookID] = current.currentTime

    context["progress"] = progress
    updateContext()
  }

  func syncContinueListening(books: [Book]) {
    let allProgress = (try? MediaProgress.fetchAll()) ?? []
    let progressByBookID = Dictionary(
      uniqueKeysWithValues: allProgress.map { ($0.bookID, $0.currentTime) }
    )

    var continueListening: [[String: Any]] = []
    var progress: [String: Double] = [:]

    for book in books {
      continueListening.append([
        "id": book.id,
        "title": book.title,
        "author": book.authorName as Any,
        "coverURL": watchCompatibleCoverURL(from: book.coverURL()) as Any,
        "duration": book.duration,
      ])

      if let currentTime = progressByBookID[book.id] {
        progress[book.id] = currentTime
      }

      if continueListening.count >= 5 { break }
    }

    for bookID in watchDownloadedBookIDs {
      if let currentTime = progressByBookID[bookID] {
        progress[bookID] = currentTime
      }
    }

    context["continueListening"] = continueListening
    context["progress"] = progress
    updateContext()

    AppLogger.watchConnectivity.info(
      "Synced \(continueListening.count) continue listening books"
    )
  }

  private func refreshContinueListening() {
    Task {
      do {
        let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()

        for section in personalized.sections {
          if section.id == "continue-listening" {
            if case .books(let books) = section.entities {
              syncContinueListening(books: books)
              AppLogger.watchConnectivity.info("Refreshed continue listening from server on watch request")
            }
            break
          }
        }
      } catch {
        AppLogger.watchConnectivity.error("Failed to fetch personalized data for watch refresh: \(error)")
      }
    }
  }

  private func refreshProgress() {
    let continueListening = context["continueListening"] as? [[String: Any]] ?? []
    var progress: [String: Double] = [:]

    let allProgress = (try? MediaProgress.fetchAll()) ?? []
    let progressByBookID = Dictionary(
      uniqueKeysWithValues: allProgress.map { ($0.bookID, $0.currentTime) }
    )

    for dict in continueListening {
      guard let bookID = dict["id"] as? String,
        let currentTime = progressByBookID[bookID]
      else { continue }
      progress[bookID] = currentTime
    }

    for bookID in watchDownloadedBookIDs {
      if let currentTime = progressByBookID[bookID] {
        progress[bookID] = currentTime
      }
    }

    if let currentID = PlayerManager.shared.current?.id,
      let currentTime = progressByBookID[currentID]
    {
      progress[currentID] = currentTime
    }

    context["progress"] = progress
    updateContext()
  }

  private func updateContext() {
    guard session?.isReachable == true else { return }
    do {
      try session?.updateApplicationContext(context)
    } catch {
      AppLogger.watchConnectivity.error(
        "Failed to sync context to watch: \(error)"
      )
    }
  }

  func sendPlaybackRate(_ rate: Float?) {
    if let rate {
      context["playbackRate"] = rate
      context["hasCurrentBook"] = true
    } else {
      context.removeValue(forKey: "playbackRate")
      context.removeValue(forKey: "hasCurrentBook")
    }

    updateContext()
  }

  func clearAllState() {
    context = [:]
    updateContext()
  }

  private func watchCompatibleCoverURL(from url: URL?) -> String? {
    guard let url = url else { return nil }

    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "width", value: "200")]
    components?.queryItems = [URLQueryItem(name: "format", value: "jpg")]
    return components?.url?.absoluteString ?? url.absoluteString
  }
}

extension WatchConnectivityManager: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      AppLogger.watchConnectivity.error(
        "Watch session activation failed: \(error)"
      )
    } else {
      AppLogger.watchConnectivity.info(
        "Watch session activated with state: \(activationState.rawValue)"
      )

      Task {
        if activationState == .activated, Audiobookshelf.shared.authentication.server != nil {
          try await Task.sleep(nanoseconds: 1_000_000_000)
          syncCachedDataToWatch()
        }
      }
    }
  }

  private func syncCachedDataToWatch() {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      AppLogger.watchConnectivity.info("No cached personalized data to sync to watch")
      return
    }

    for section in personalized.sections {
      if section.id == "continue-listening" {
        if case .books(let books) = section.entities {
          syncContinueListening(books: books)
          AppLogger.watchConnectivity.info(
            "Synced cached continue listening to watch on activation"
          )
        }
        break
      }
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    AppLogger.watchConnectivity.info("Watch session became inactive")
  }

  func sessionDidDeactivate(_ session: WCSession) {
    AppLogger.watchConnectivity.info("Watch session deactivated, reactivating...")
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    AppLogger.watchConnectivity.debug("Received message from watch: \(message)")

    guard let command = message["command"] as? String else { return }

    Task { @MainActor in
      switch command {
      case "play":
        if let bookID = message["bookID"] as? String {
          handlePlayCommand(bookID: bookID)
        } else {
          PlayerManager.shared.current?.onPlayTapped()
        }
      case "pause":
        PlayerManager.shared.current?.onPauseTapped()
      case "skipForward":
        let interval = UserDefaults.standard.double(forKey: "skipForwardInterval")
        PlayerManager.shared.current?.onSkipForwardTapped(seconds: interval)
      case "skipBackward":
        let interval = UserDefaults.standard.double(forKey: "skipBackwardInterval")
        PlayerManager.shared.current?.onSkipBackwardTapped(seconds: interval)
      case "changePlaybackRate":
        if let rate = message["rate"] as? Float {
          PlayerManager.shared.current?.speed.onSpeedChanged(rate)
        }
      case "refreshContinueListening":
        refreshContinueListening()
      case "requestContext":
        refreshProgress()
      case "reportProgress":
        if let sessionID = message["sessionID"] as? String,
          let currentTime = message["currentTime"] as? Double,
          let timeListened = message["timeListened"] as? Double
        {
          handleProgressReport(
            sessionID: sessionID,
            currentTime: currentTime,
            timeListened: timeListened
          )
        }
      case "syncDownloadedBooks":
        if let bookIDs = message["bookIDs"] as? [String] {
          watchDownloadedBookIDs = bookIDs
          AppLogger.watchConnectivity.info(
            "Received \(bookIDs.count) downloaded book IDs from watch"
          )
          refreshProgress()
        }
      default:
        AppLogger.watchConnectivity.warning(
          "Unknown command from watch: \(command)"
        )
      }
    }
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    AppLogger.watchConnectivity.debug("Received message with reply from watch: \(message)")

    guard let command = message["command"] as? String else {
      replyHandler(["error": "Missing command"])
      return
    }

    Task {
      switch command {
      case "startSession":
        guard let bookID = message["bookID"] as? String else {
          replyHandler(["error": "Missing bookID"])
          return
        }

        let forDownload = message["forDownload"] as? Bool ?? false
        await handleStartSession(
          bookID: bookID,
          forDownload: forDownload,
          replyHandler: replyHandler
        )

      default:
        replyHandler(["error": "Unknown command: \(command)"])
      }
    }
  }

  private func handleStartSession(
    bookID: String,
    forDownload: Bool,
    replyHandler: @escaping ([String: Any]) -> Void
  ) async {
    do {
      guard
        let serverURL = Audiobookshelf.shared.authentication.serverURL,
        let token = Audiobookshelf.shared.authentication.server?.token
      else {
        replyHandler(["error": "No server URL or token"])
        return
      }

      let book: Book
      let sessionID: String?
      let audioTracks: [Book.Media.Track]

      if forDownload {
        book = try await Audiobookshelf.shared.books.fetch(id: bookID)
        sessionID = nil
        audioTracks = book.tracks ?? []
      } else {
        let playSession = try await Audiobookshelf.shared.sessions.start(
          itemID: bookID,
          forceTranscode: true,
          sessionType: .watch
        )
        book = playSession.libraryItem
        sessionID = playSession.id
        audioTracks = playSession.audioTracks ?? []
      }

      let tracks: [[String: Any]] = audioTracks.map { audioTrack in
        let trackURL: String
        if forDownload, let ino = audioTrack.ino {
          var url = serverURL.appendingPathComponent("api/items/\(bookID)/file/\(ino)/download")
          switch token {
          case .legacy(let tokenValue):
            url.append(queryItems: [URLQueryItem(name: "token", value: tokenValue)])
          case .bearer(let accessToken, _, _):
            url.append(queryItems: [URLQueryItem(name: "token", value: accessToken)])
          }
          trackURL = url.absoluteString
        } else if let sessionID = sessionID {
          let baseURLString = serverURL.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
          )
          trackURL =
            "\(baseURLString)/public/session/\(sessionID)/track/\(audioTrack.index)"
        } else {
          trackURL = ""
        }

        return [
          "index": audioTrack.index,
          "duration": audioTrack.duration,
          "size": audioTrack.metadata?.size ?? 0,
          "ext": audioTrack.metadata?.ext ?? "",
          "url": trackURL,
        ]
      }

      let chapters: [[String: Any]] =
        book.chapters?.enumerated().map { index, chapter in
          [
            "id": index,
            "title": chapter.title,
            "start": chapter.start,
            "end": chapter.end,
          ]
        } ?? []

      if let sessionID = sessionID {
        AppLogger.watchConnectivity.info(
          "Created session \(sessionID) for book \(bookID), forDownload=\(forDownload)"
        )
      } else {
        AppLogger.watchConnectivity.info(
          "Fetched book \(bookID) for download, forDownload=\(forDownload)"
        )
      }

      let coverURLString = watchCompatibleCoverURL(from: book.coverURL())

      replyHandler([
        "id": bookID,
        "sessionID": sessionID ?? "",
        "title": book.title,
        "authorName": book.authorName ?? "",
        "coverURL": coverURLString ?? "",
        "duration": book.duration,
        "tracks": tracks,
        "chapters": chapters,
      ])
    } catch {
      AppLogger.watchConnectivity.error("Failed to start session: \(error)")
      replyHandler(["error": error.localizedDescription])
    }
  }

  private func handleProgressReport(sessionID: String, currentTime: Double, timeListened: Double) {
    Task {
      do {
        try await Audiobookshelf.shared.sessions.sync(
          sessionID,
          timeListened: timeListened,
          currentTime: currentTime
        )
        AppLogger.watchConnectivity.debug("Synced watch progress: \(currentTime)s")
      } catch {
        AppLogger.watchConnectivity.error(
          "Failed to sync watch progress: \(error)"
        )
      }
    }
  }

  private func handlePlayCommand(bookID: String) {
    Task { @MainActor in
      do {
        if let book = try LocalBook.fetch(bookID: bookID) {
          PlayerManager.shared.setCurrent(book)
          PlayerManager.shared.current?.onPlayTapped()
          PlayerManager.shared.showFullPlayer()
        } else {
          AppLogger.watchConnectivity.info("Book not found locally, fetching from server...")
          let session = try await Audiobookshelf.shared.sessions.start(
            itemID: bookID,
            forceTranscode: false
          )

          PlayerManager.shared.setCurrent(session.libraryItem)
          PlayerManager.shared.current?.onPlayTapped()
          PlayerManager.shared.showFullPlayer()
        }
      } catch {
        AppLogger.watchConnectivity.error(
          "Failed to handle play command: \(error)"
        )
      }
    }
  }
}
