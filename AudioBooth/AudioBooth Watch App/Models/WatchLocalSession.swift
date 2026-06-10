import Foundation

struct WatchLocalSession: Codable {
  let id: String
  let bookID: String
  let duration: Double
  let startTime: Double
  var currentTime: Double
  var timeListening: Double
  let startedAt: Date
  var updatedAt: Date
}

final class WatchLocalSessionStore {
  static let shared = WatchLocalSessionStore()

  private let sessionsKey = "local_sessions"

  private(set) var sessions: [WatchLocalSession]

  private init() {
    guard let data = UserDefaults.standard.data(forKey: sessionsKey),
      let sessions = try? JSONDecoder().decode([WatchLocalSession].self, from: data)
    else {
      self.sessions = []
      return
    }
    self.sessions = sessions
  }

  func record(bookID: String, currentTime: Double, timeListened: Double, duration: Double) {
    var updatedSessions = sessions
    if let index = updatedSessions.firstIndex(where: { $0.bookID == bookID }) {
      updatedSessions[index].currentTime = currentTime
      updatedSessions[index].timeListening += timeListened
      updatedSessions[index].updatedAt = Date()
    } else {
      updatedSessions.append(
        WatchLocalSession(
          id: UUID().uuidString,
          bookID: bookID,
          duration: duration,
          startTime: max(0, currentTime - timeListened),
          currentTime: currentTime,
          timeListening: timeListened,
          startedAt: Date().addingTimeInterval(-timeListened),
          updatedAt: Date()
        )
      )
    }
    save(updatedSessions)
  }

  func remove(ids: [String]) {
    save(sessions.filter { !ids.contains($0.id) })
  }

  private func save(_ sessions: [WatchLocalSession]) {
    self.sessions = sessions
    guard let data = try? JSONEncoder().encode(sessions) else { return }
    UserDefaults.standard.set(data, forKey: sessionsKey)
  }
}
