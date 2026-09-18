import API
import Foundation
import Logging
import Models

final class SessionsContentModel: SessionsContent.Model {
  private let bookID: String
  private let bookDuration: TimeInterval
  private var sessionsService: SessionService { Audiobookshelf.shared.sessions }
  private var currentPage: Int
  private var allSessions: [API.SessionSync] = []

  init(
    bookID: String,
    bookDuration: TimeInterval,
    sessions: [API.SessionSync],
    currentPage: Int,
    numPages: Int
  ) {
    self.bookID = bookID
    self.bookDuration = bookDuration
    self.currentPage = currentPage
    self.allSessions = sessions

    super.init(
      sessions: Self.mapSessions(sessions, bookDuration: bookDuration),
      hasMorePages: currentPage < numPages - 1
    )
  }

  override func onRestoreConfirmed(_ session: SessionsContent.Session) {
    pendingRestore = nil

    let sessionDuration = allSessions.first(where: { $0.id == session.id })?.duration ?? 0
    let duration = bookDuration > 0 ? bookDuration : sessionDuration
    let progress = duration > 0 ? min(1, session.currentTime / duration) : 0

    Task {
      do {
        try await Audiobookshelf.shared.progress.update(
          bookID: bookID,
          currentTime: session.currentTime,
          duration: duration
        )

        try MediaProgress.updateProgress(
          for: bookID,
          currentTime: session.currentTime,
          duration: duration,
          progress: progress
        )

        if let player = PlayerManager.shared.current as? BookPlayerModel, player.id == bookID {
          player.seekToTime(session.currentTime)
        }
      } catch {
        AppLogger.viewModel.error("Failed to restore progress from session: \(error)")
      }
    }
  }

  override func onLoadMore() {
    guard !isLoadingMore, hasMorePages else { return }

    isLoadingMore = true
    Task {
      do {
        let response = try await sessionsService.getListeningSessions(
          itemID: bookID,
          page: currentPage + 1
        )
        currentPage = response.page
        allSessions.append(contentsOf: response.sessions)
        sessions = Self.mapSessions(allSessions, bookDuration: bookDuration)
        hasMorePages = response.page < response.numPages - 1
      } catch {
        AppLogger.viewModel.error("Failed to load more listening sessions: \(error)")
      }
      isLoadingMore = false
    }
  }

  private static func mapSessions(
    _ apiSessions: [API.SessionSync],
    bookDuration: TimeInterval
  ) -> [SessionsContent.Session] {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "d"

    let monthFormatter = DateFormatter()
    monthFormatter.dateFormat = "MMM"

    let yearFormatter = DateFormatter()
    yearFormatter.dateFormat = "yyyy"

    let dateKeyFormatter = DateFormatter()
    dateKeyFormatter.dateFormat = "yyyy-MM-dd"

    let timeFormatter = DateFormatter()
    timeFormatter.dateStyle = .none
    timeFormatter.timeStyle = .short

    let currentYear = yearFormatter.string(from: Date())

    return
      apiSessions
      .sorted { $0.startedAt > $1.startedAt }
      .map { session in
        let startDate = Date(timeIntervalSince1970: TimeInterval(session.startedAt) / 1000)
        let endDate = Date(timeIntervalSince1970: TimeInterval(session.updatedAt) / 1000)

        let timeListening = session.timeListening ?? 0
        let progress: Double
        if bookDuration > 0 {
          progress = min(1.0, session.currentTime / bookDuration)
        } else {
          progress = 0
        }

        let sessionYear = yearFormatter.string(from: startDate)
        let year: String? = sessionYear != currentYear ? sessionYear : nil

        return SessionsContent.Session(
          id: session.id,
          dateKey: dateKeyFormatter.string(from: startDate),
          dayNumber: dayFormatter.string(from: startDate),
          monthAbbreviation: monthFormatter.string(from: startDate).uppercased(),
          year: year,
          timeRange: "\(timeFormatter.string(from: startDate)) – \(timeFormatter.string(from: endDate))",
          durationText: formatDuration(timeListening),
          progress: progress,
          currentTime: session.currentTime,
          positionText: formatDuration(session.currentTime)
        )
      }
  }

  private static func formatDuration(_ seconds: Double) -> String {
    if seconds < 60 {
      Duration.seconds(seconds)
        .formatted(.units(allowed: [.seconds], width: .narrow))
    } else {
      Duration.seconds(seconds)
        .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
  }
}
