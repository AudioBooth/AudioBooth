import Foundation

enum PositionSyncOffer {
  enum Direction: String, Sendable {
    case toAudiobook
    case toEbook
  }

  enum Dismissal: String, Sendable {
    case position
    case session
    case book
  }

  private struct Checkpoint: Codable {
    let audioTime: TimeInterval
    let ebookProgress: Double
  }

  static let minimumGap: TimeInterval = 300

  private static let positionKey = "positionSyncDismissed"
  private static let bookKey = "positionSyncDismissedBooks"
  private static let checkpointKey = "positionSyncCheckpoints"
  private static let secondsBeforeRechecking: TimeInterval = 120
  private static let progressBeforeRechecking = 0.002

  private static var sessionDismissals: Set<String> = []

  static func needsCheck(
    _ direction: Direction,
    bookID: String,
    audioTime: TimeInterval,
    ebookProgress: Double
  ) -> Bool {
    guard let checkpoint = checkpoints()[key(direction, bookID)] else { return true }

    return abs(checkpoint.audioTime - audioTime) > secondsBeforeRechecking
      || abs(checkpoint.ebookProgress - ebookProgress) > progressBeforeRechecking
  }

  static func recordCheck(
    _ direction: Direction,
    bookID: String,
    audioTime: TimeInterval,
    ebookProgress: Double
  ) {
    var all = checkpoints()
    all[key(direction, bookID)] = Checkpoint(audioTime: audioTime, ebookProgress: ebookProgress)

    guard let encoded = try? JSONEncoder().encode(all) else { return }
    UserDefaults.standard.set(encoded, forKey: checkpointKey)
  }

  static func dismissal(
    _ direction: Direction,
    bookID: String,
    at progress: Double,
    duration: TimeInterval
  ) -> Dismissal? {
    let key = key(direction, bookID)

    if sessionDismissals.contains(key) { return .session }
    if stored(bookKey)[key] != nil { return .book }

    guard let dismissed = stored(positionKey)[key] else { return nil }
    guard duration > 0, duration.isFinite else { return .position }

    return abs(dismissed - progress) * duration < minimumGap ? .position : nil
  }

  static func dismiss(
    _ direction: Direction,
    bookID: String,
    at progress: Double,
    scope: Dismissal = .position
  ) {
    let key = key(direction, bookID)

    switch scope {
    case .position:
      var all = stored(positionKey)
      all[key] = progress
      save(all, to: positionKey)

    case .session:
      sessionDismissals.insert(key)

    case .book:
      var all = stored(bookKey)
      all[key] = 1
      save(all, to: bookKey)
    }
  }

  private static func key(_ direction: Direction, _ bookID: String) -> String {
    "\(direction.rawValue):\(bookID)"
  }

  private static func checkpoints() -> [String: Checkpoint] {
    guard let data = UserDefaults.standard.data(forKey: checkpointKey),
      let decoded = try? JSONDecoder().decode([String: Checkpoint].self, from: data)
    else {
      return [:]
    }
    return decoded
  }

  private static func stored(_ key: String) -> [String: Double] {
    guard let data = UserDefaults.standard.data(forKey: key),
      let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
    else {
      return [:]
    }
    return decoded
  }

  private static func save(_ values: [String: Double], to key: String) {
    guard let encoded = try? JSONEncoder().encode(values) else { return }
    UserDefaults.standard.set(encoded, forKey: key)
  }
}
