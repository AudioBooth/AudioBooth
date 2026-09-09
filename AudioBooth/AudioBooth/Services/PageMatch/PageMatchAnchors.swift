import Foundation
import Logging

nonisolated enum PageMatchAnchors {
  struct Anchor: Codable, Sendable {
    let page: Int
    let time: TimeInterval
    let secondsPerPage: TimeInterval?
  }

  private static let storageKey = "pageMatchAnchors"
  private static let maximumPerBook = 5
  private static let minimumPagesApart = 3

  static func anchors(for bookID: String) -> [Anchor] {
    stored()[bookID] ?? []
  }

  static func record(_ anchor: Anchor, for bookID: String) {
    var all = stored()
    var existing = all[bookID] ?? []

    existing.removeAll { $0.page == anchor.page }
    existing.append(anchor)
    all[bookID] = Array(existing.suffix(maximumPerBook))

    guard let encoded = try? JSONEncoder().encode(all) else { return }
    UserDefaults.standard.set(encoded, forKey: storageKey)

    AppLogger.readAlong.info(
      "Page Match: recorded page \(anchor.page) at \(Int(anchor.time))s for \(bookID)"
    )
  }

  static func estimate(page: Int, for bookID: String) -> TimeInterval? {
    let anchors = anchors(for: bookID).sorted { $0.page < $1.page }
    guard let first = anchors.first, let last = anchors.last else { return nil }

    if last.page - first.page >= minimumPagesApart {
      let rate = (last.time - first.time) / Double(last.page - first.page)
      guard rate > 0 else { return nil }
      return max(0, first.time + Double(page - first.page) * rate)
    }

    let nearest = anchors.min { abs($0.page - page) < abs($1.page - page) }
    guard let nearest, let secondsPerPage = nearest.secondsPerPage, secondsPerPage > 0 else {
      return nil
    }
    return max(0, nearest.time + Double(page - nearest.page) * secondsPerPage)
  }

  private static func stored() -> [String: [Anchor]] {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([String: [Anchor]].self, from: data)
    else {
      return [:]
    }
    return decoded
  }
}
