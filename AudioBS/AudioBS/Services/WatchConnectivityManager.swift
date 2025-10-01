import Audiobookshelf
import Combine
import Foundation
import Models
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  private var session: WCSession?
  private var cancellables = Set<AnyCancellable>()

  private override init() {
    super.init()

    if WCSession.isSupported() {
      session = WCSession.default
      session?.delegate = self
      session?.activate()
    }
  }

  func sendPlaybackState(
    isPlaying: Bool,
    progress: Double,
    current: Double,
    remaining: Double,
    total: Double,
    totalTimeRemaining: Double,
    bookID: String,
    title: String,
    author: String?,
    coverURL: URL?,
    playbackSpeed: Float
  ) {
    guard let session = session, session.isReachable else { return }

    var context = session.applicationContext

    context["isPlaying"] = isPlaying
    context["progress"] = progress
    context["current"] = current
    context["remaining"] = remaining
    context["total"] = total
    context["totalTimeRemaining"] = totalTimeRemaining
    context["bookID"] = bookID
    context["title"] = title
    context["author"] = author ?? ""
    context["coverURL"] = coverURL?.absoluteString ?? ""
    context["playbackSpeed"] = playbackSpeed
    context["hasActivePlayer"] = true

    do {
      try session.updateApplicationContext(context)
    } catch {
      print("Failed to send playback state to watch: \(error)")
    }
  }

  func clearPlaybackState() {
    guard let session = session, session.isReachable else { return }

    var context = session.applicationContext
    context["hasActivePlayer"] = false
    context.removeValue(forKey: "isPlaying")
    context.removeValue(forKey: "progress")
    context.removeValue(forKey: "current")
    context.removeValue(forKey: "remaining")
    context.removeValue(forKey: "total")
    context.removeValue(forKey: "totalTimeRemaining")
    context.removeValue(forKey: "bookID")
    context.removeValue(forKey: "title")
    context.removeValue(forKey: "author")
    context.removeValue(forKey: "coverURL")
    context.removeValue(forKey: "playbackSpeed")

    do {
      try session.updateApplicationContext(context)
    } catch {
      print("Failed to clear playback state on watch: \(error)")
    }
  }

  func syncAuthCredentials(serverURL: URL, token: String) {
    guard let session = session else { return }

    var context = session.applicationContext
    context["authServerURL"] = serverURL.absoluteString
    context["authToken"] = token

    do {
      try session.updateApplicationContext(context)
      print("Synced auth credentials to watch")
    } catch {
      print("Failed to sync auth credentials to watch: \(error)")
    }
  }

  func clearAuthCredentials() {
    guard let session = session else { return }

    var context = session.applicationContext
    context.removeValue(forKey: "authServerURL")
    context.removeValue(forKey: "authToken")

    do {
      try session.updateApplicationContext(context)
      print("Cleared auth credentials on watch")
    } catch {
      print("Failed to clear auth credentials on watch: \(error)")
    }
  }

  func syncLibrary(_ library: Library) {
    guard let session = session else { return }

    var context = session.applicationContext
    if let libraryData = try? JSONEncoder().encode(library) {
      context["library"] = libraryData
      do {
        try session.updateApplicationContext(context)
        print("Synced library to watch: \(library.name)")
      } catch {
        print("Failed to sync library to watch: \(error)")
      }
    }
  }

  func clearLibrary() {
    guard let session = session else { return }

    var context = session.applicationContext
    context.removeValue(forKey: "library")

    do {
      try session.updateApplicationContext(context)
      print("Cleared library on watch")
    } catch {
      print("Failed to clear library on watch: \(error)")
    }
  }

}

extension WatchConnectivityManager: WCSessionDelegate {
  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error = error {
      print("Watch session activation failed: \(error)")
    } else {
      print("Watch session activated with state: \(activationState.rawValue)")
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    print("Watch session became inactive")
  }

  func sessionDidDeactivate(_ session: WCSession) {
    print("Watch session deactivated, reactivating...")
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    print("Received message from watch: \(message)")

    guard let command = message["command"] as? String else { return }

    Task { @MainActor in
      switch command {
      case "togglePlayback":
        PlayerManager.shared.current?.onTogglePlaybackTapped()
      case "skipForward":
        PlayerManager.shared.current?.onSkipForwardTapped()
      case "skipBackward":
        PlayerManager.shared.current?.onSkipBackwardTapped()
      case "play":
        if let bookID = message["bookID"] as? String {
          handlePlayCommand(bookID: bookID)
        }
      default:
        print("Unknown command from watch: \(command)")
      }
    }
  }

  private func handlePlayCommand(bookID: String) {
    Task { @MainActor in
      do {
        if let recentItem = try RecentlyPlayedItem.fetch(bookID: bookID) {
          PlayerManager.shared.setCurrent(recentItem)
        } else {
          print("Recently played item not found for bookID: \(bookID)")
        }
      } catch {
        print("Failed to fetch recently played item: \(error)")
      }
    }
  }
}
