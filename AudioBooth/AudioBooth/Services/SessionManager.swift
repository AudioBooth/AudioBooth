import API
import AVFoundation
import BackgroundTasks
import Foundation
import Logging
import MediaPlayer
import Models

final class SessionManager {
  static let shared = SessionManager()

  private let taskIdentifier = "me.jgrenier.AudioBS.close-session"
  private let sessionIDKey = "activeSessionID"
  private let retryCountKey = "sessionCloseRetryCount"
  private let inactivityTimeout: TimeInterval = 10 * 60
  private let audiobookshelf = Audiobookshelf.shared
  private let downloadManager = DownloadManager.shared

  private(set) var current: PlaybackSession?
  private var lastSyncAt = Date()
  private var inactivityTask: Task<Void, Never>?

  private init() {
    registerBackgroundTask()
  }

  private func startSession(
    itemID: String,
    item: LocalBook?,
    mediaProgress: MediaProgress,
    forceTranscode: Bool
  ) async throws -> (session: Session, updatedItem: LocalBook) {
    AppLogger.session.info("Fetching session from server...")

    let audiobookshelfSession = try await audiobookshelf.sessions.start(
      itemID: itemID,
      forceTranscode: forceTranscode,
      timeout: item == nil ? 30 : 10
    )

    guard let session = Session(from: audiobookshelfSession) else {
      throw SessionError.failedToCreateSession
    }

    let updatedItem: LocalBook

    if let item {
      item.chapters = audiobookshelfSession.chapters?.map(Chapter.init) ?? []
      updatedItem = item
      AppLogger.session.debug("Updated session with chapters")
    } else {
      let newItem = LocalBook(from: audiobookshelfSession.libraryItem)
      try? newItem.save()
      updatedItem = newItem
      AppLogger.session.debug("Created new item from session")
    }

    if audiobookshelfSession.currentTime > mediaProgress.currentTime {
      AppLogger.session.info(
        "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s (local was: \(mediaProgress.currentTime)s)"
      )
      mediaProgress.currentTime = audiobookshelfSession.currentTime
    }

    let playbackSession = PlaybackSession(
      id: session.id,
      libraryItemID: itemID,
      startTime: mediaProgress.currentTime,
      currentTime: mediaProgress.currentTime,
      duration: updatedItem.duration,
      baseURL: session.url,
      displayTitle: updatedItem.title,
      displayAuthor: updatedItem.authorNames
    )
    try playbackSession.save()
    current = playbackSession

    UserDefaults.standard.set(0, forKey: retryCountKey)
    scheduleSessionClose()

    AppLogger.session.info("Session setup completed successfully")
    return (session, updatedItem)
  }

  func closeSession(
    isDownloaded: Bool = false
  ) async throws {
    guard let session = current else {
      AppLogger.session.debug("Session already closed or no session to close")
      return
    }

    session.updatedAt = Date()
    try session.save()

    if session.isRemote {
      if session.pendingListeningTime > 0 {
        do {
          try await audiobookshelf.sessions.sync(
            session.id,
            timeListened: session.pendingListeningTime,
            currentTime: session.currentTime
          )
          session.timeListening += session.pendingListeningTime
          session.pendingListeningTime = 0
          try session.save()
          AppLogger.session.debug("Synced final progress before closing remote session")
        } catch {
          AppLogger.session.error(
            "Failed to sync session progress before close: \(error)"
          )
        }
      }

      do {
        try await audiobookshelf.sessions.close(session.id)
        AppLogger.session.info(
          "Successfully closed remote session: \(session.id)"
        )
        UserDefaults.standard.removeObject(forKey: sessionIDKey)
        UserDefaults.standard.removeObject(forKey: retryCountKey)
        cancelScheduledSessionClose()
      } catch {
        AppLogger.session.error("Failed to close remote session: \(error)")

        if isDownloaded {
          AppLogger.session.info(
            "Book is downloaded, clearing session to allow local session creation"
          )
          current = nil
          UserDefaults.standard.removeObject(forKey: sessionIDKey)
          UserDefaults.standard.removeObject(forKey: retryCountKey)
          cancelScheduledSessionClose()
          return
        }

        let retryCount = UserDefaults.standard.integer(forKey: retryCountKey)
        guard let backoffDelay = calculateBackoffDelay(retryCount: retryCount) else {
          AppLogger.session.warning(
            "Maximum retry attempts reached. Giving up on closing session \(session.id). Session will auto-expire on server after 24h."
          )
          current = nil
          UserDefaults.standard.removeObject(forKey: sessionIDKey)
          UserDefaults.standard.removeObject(forKey: retryCountKey)
          cancelScheduledSessionClose()
          return
        }

        let newRetryCount = retryCount + 1
        UserDefaults.standard.set(newRetryCount, forKey: retryCountKey)

        AppLogger.session.info(
          "Rescheduling session close with backoff delay: \(backoffDelay)s (retry: \(newRetryCount))"
        )

        scheduleSessionClose(customDelay: backoffDelay)
        throw error
      }
      current = nil
    } else {
      do {
        let sessionSync = SessionSync(session)
        try await audiobookshelf.sessions.syncLocalSession(sessionSync)
        session.timeListening += session.pendingListeningTime
        session.pendingListeningTime = 0
        try session.save()
        AppLogger.session.info(
          "Successfully closed and synced local session: \(session.id)"
        )
      } catch {
        try session.save()
        AppLogger.session.error(
          "Failed to sync local session: \(error). Session will be synced on next app startup."
        )
      }
      current = nil
    }
  }

  func ensureSession(
    itemID: String,
    item: LocalBook?,
    mediaProgress: MediaProgress,
    forceTranscode: Bool
  ) async throws -> LocalBook {
    if let current, current.libraryItemID != itemID {
      AppLogger.session.info(
        "Session exists for different book, server will close old session when starting new one"
      )
      self.current = nil
      cancelScheduledSessionClose()
    }

    if let item, let current, current.libraryItemID == itemID {
      AppLogger.session.debug(
        "Session already exists for this book, reusing: \(current.id)"
      )
      return item
    }

    if downloadManager.downloadStates[itemID] == .downloaded, let item {
      startLocalSession(
        libraryItemID: itemID,
        item: item,
        mediaProgress: mediaProgress
      )
      AppLogger.session.info("Created local session for offline stats tracking")
      return item
    }

    do {
      let result = try await startSession(
        itemID: itemID,
        item: item,
        mediaProgress: mediaProgress,
        forceTranscode: forceTranscode
      )
      return result.updatedItem
    } catch {
      AppLogger.session.warning("Failed to create remote session: \(error)")
      throw error
    }
  }

  private func startLocalSession(
    libraryItemID: String,
    item: LocalBook,
    mediaProgress: MediaProgress
  ) {
    let session = PlaybackSession(
      libraryItemID: libraryItemID,
      startTime: mediaProgress.currentTime,
      currentTime: mediaProgress.currentTime,
      duration: item.duration,
      displayTitle: item.title,
      displayAuthor: item.authorNames
    )
    try? session.save()
    current = session
    AppLogger.session.info("Started local session: \(session.id)")
  }

  func syncProgress(currentTime: TimeInterval) async throws {
    guard let session = current else {
      throw SessionError.noActiveSession
    }

    let now = Date()

    session.currentTime = currentTime
    session.updatedAt = now
    try session.save()

    guard session.pendingListeningTime >= 20, now.timeIntervalSince(lastSyncAt) >= 10 else {
      return
    }

    lastSyncAt = now

    if session.isRemote {
      do {
        try await audiobookshelf.sessions.sync(
          session.id,
          timeListened: session.pendingListeningTime,
          currentTime: currentTime
        )
        session.timeListening += session.pendingListeningTime
        session.pendingListeningTime = 0
        try session.save()
        scheduleSessionClose()
        AppLogger.session.info("Successfully synced remote session: \(session.id)")
        return
      } catch {
        AppLogger.session.error("Failed to sync remote session: \(error)")
        throw error
      }
    } else {
      do {
        try await audiobookshelf.sessions.syncLocalSession(SessionSync(session))
        session.timeListening += session.pendingListeningTime
        session.pendingListeningTime = 0
        try session.save()
        AppLogger.session.info("Successfully synced local session: \(session.id)")
      } catch {
        lastSyncAt = now.advanced(by: min(session.pendingListeningTime * 2, 600))
        AppLogger.session.error("Failed to sync local session: \(error)")
        throw error
      }
    }
  }

  private func calculateBackoffDelay(retryCount: Int) -> TimeInterval? {
    let backoffSchedule: [TimeInterval] = [
      10 * 60,
      30 * 60,
      60 * 60,
      2 * 60 * 60,
      4 * 60 * 60,
      4 * 60 * 60,
      4 * 60 * 60,
      4 * 60 * 60,
    ]

    guard retryCount < backoffSchedule.count else { return nil }

    return backoffSchedule[retryCount]
  }

  private func registerBackgroundTask() {
    let success = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: taskIdentifier,
      using: nil
    ) { [weak self] task in
      AppLogger.session.debug("Task triggered")
      self?.handleBackgroundTask(task as! BGAppRefreshTask)
    }

    if success {
      AppLogger.session.info(
        "Background task handler registered successfully for: \(self.taskIdentifier)"
      )
    } else {
      AppLogger.session.warning(
        "Failed to register background task handler for: \(self.taskIdentifier)"
      )
      AppLogger.session.debug(
        "Note: This is normal if registration was already done, or if running in certain environments"
      )
    }
  }

  private func scheduleSessionClose(customDelay: TimeInterval? = nil) {
    guard let sessionID = current?.id else {
      AppLogger.session.warning("Cannot schedule session close - no active session")
      return
    }

    UserDefaults.standard.set(sessionID, forKey: sessionIDKey)

    let delay = customDelay ?? inactivityTimeout
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: delay)

    do {
      try BGTaskScheduler.shared.submit(request)
      AppLogger.session.info(
        "Scheduled background task to close session \(sessionID) after \(delay)s"
      )
    } catch let error as NSError {
      if error.code == 1 {
        AppLogger.session.warning(
          "Background tasks unavailable (Background App Refresh may be disabled). Session will close on foreground instead."
        )
      } else {
        AppLogger.session.error("Failed to schedule background task: \(error)")
      }
    }
  }

  private func cancelScheduledSessionClose() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    UserDefaults.standard.removeObject(forKey: sessionIDKey)
    AppLogger.session.debug("Canceled scheduled session close background task")
  }

  private func handleBackgroundTask(_ task: BGAppRefreshTask) {
    let retryCount = UserDefaults.standard.integer(forKey: retryCountKey)
    AppLogger.session.info(
      "Background task executing - checking if session should be closed (retry: \(retryCount))"
    )

    let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
    let playbackRate = nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0.0
    let carPlayConnected = AVAudioSession.sharedInstance().isCarPlayConnected

    if playbackRate > 0 {
      AppLogger.session.info("Playback is still active, rescheduling session close")
      UserDefaults.standard.set(0, forKey: retryCountKey)
      scheduleSessionClose()
      task.setTaskCompleted(success: false)
    } else if carPlayConnected {
      AppLogger.session.info("CarPlay is connected, rescheduling session close")
      UserDefaults.standard.set(0, forKey: retryCountKey)
      scheduleSessionClose()
      task.setTaskCompleted(success: false)
    } else {
      AppLogger.session.info("Playback is not active, attempting to close session")
      Task {
        do {
          try await closeSession()
          task.setTaskCompleted(success: true)
        } catch {
          task.setTaskCompleted(success: false)
        }
      }
    }
  }

  func clearSession() {
    current = nil
    UserDefaults.standard.set(0, forKey: retryCountKey)
    cancelScheduledSessionClose()
    cancelInactivityTask()
  }

  func syncUnsyncedSessions() {
    AppLogger.session.info("Starting bulk sync of unsynced sessions")

    let unsyncedSessions: [PlaybackSession]
    do {
      unsyncedSessions = try PlaybackSession.fetchUnsynced()
    } catch {
      AppLogger.session.error("Failed to fetch unsynced sessions: \(error)")
      return
    }

    guard !unsyncedSessions.isEmpty else {
      AppLogger.session.debug("No unsynced sessions to sync")
      return
    }

    AppLogger.session.info(
      "Found \(unsyncedSessions.count) unsynced sessions to sync"
    )

    let sessionSyncs = unsyncedSessions.map { SessionSync($0) }

    Task {
      do {
        try await audiobookshelf.sessions.syncLocalSessions(sessionSyncs)

        for session in unsyncedSessions {
          session.timeListening += session.pendingListeningTime
          session.pendingListeningTime = 0
          try session.save()
        }

        AppLogger.session.info(
          "Successfully synced \(unsyncedSessions.count) sessions"
        )
      } catch {
        AppLogger.session.error(
          "Failed to bulk sync sessions: \(error). Will retry on next startup."
        )
      }
    }
  }

  func notifyPlaybackStopped() {
    AppLogger.session.debug("Playback stopped - starting inactivity countdown")
    startInactivityTask()
  }

  func notifyPlaybackStarted() {
    AppLogger.session.debug("Playback started - canceling inactivity countdown")
    cancelInactivityTask()
  }

  private func startInactivityTask() {
    cancelInactivityTask()

    inactivityTask = Task {
      do {
        try await Task.sleep(for: .seconds(inactivityTimeout))

        guard !Task.isCancelled else {
          AppLogger.session.debug("Inactivity task was cancelled")
          return
        }

        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let playbackRate = nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0.0
        let carPlayConnected = AVAudioSession.sharedInstance().isCarPlayConnected

        if playbackRate > 0 {
          AppLogger.session.info(
            "Inactivity timeout reached but playback is active - not closing session"
          )
          return
        }

        if carPlayConnected {
          AppLogger.session.info(
            "Inactivity timeout reached but CarPlay is connected - not closing session"
          )
          return
        }

        AppLogger.session.info("Inactivity timeout reached - closing session")
        try? await closeSession()
      } catch {
        AppLogger.session.debug("Inactivity task sleep was interrupted: \(error)")
      }
    }
  }

  private func cancelInactivityTask() {
    inactivityTask?.cancel()
    inactivityTask = nil
  }

  enum SessionError: Error {
    case noActiveSession
    case failedToCreateSession
  }
}

extension SessionSync {
  init(_ session: PlaybackSession) {
    self.init(
      id: session.id,
      libraryItemId: session.libraryItemID,
      duration: session.duration,
      startTime: session.startTime,
      currentTime: session.currentTime,
      timeListening: session.timeListening + session.pendingListeningTime,
      startedAt: Int(session.startedAt.timeIntervalSince1970 * 1000),
      updatedAt: Int(session.updatedAt.timeIntervalSince1970 * 1000)
    )
  }
}
