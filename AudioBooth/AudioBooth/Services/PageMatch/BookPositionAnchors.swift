import Foundation
import Logging

nonisolated enum BookPositionAnchors {
  struct Anchor: Codable, Sendable {
    let word: Int
    let time: TimeInterval
  }

  struct Estimate: Sendable {
    let time: TimeInterval
    let isInterpolated: Bool
  }

  private static let storageKey = "bookPositionAnchors"
  private static let maximumPerBook = 8
  private static let minimumWordsApart = 200
  private static let minimumSpanWords = 500
  private static let maximumExtrapolationWords = 5000

  static func anchors(for bookID: String) -> [Anchor] {
    stored()[bookID] ?? []
  }

  static func record(_ anchor: Anchor, for bookID: String) {
    var all = stored()
    var existing = all[bookID] ?? []

    existing.removeAll { abs($0.word - anchor.word) < minimumWordsApart }
    existing.append(anchor)
    while existing.count > maximumPerBook {
      existing.removeFirst()
    }
    all[bookID] = existing

    guard let encoded = try? JSONEncoder().encode(all) else { return }
    UserDefaults.standard.set(encoded, forKey: storageKey)

    AppLogger.readAlong.info(
      "Book position: recorded ebook word \(anchor.word) at \(Int(anchor.time))s for \(bookID)"
    )
  }

  static func estimate(word: Int, for bookID: String) -> Estimate? {
    let sorted = anchors(for: bookID).sorted { $0.word < $1.word }
    guard let first = sorted.first, let last = sorted.last, sorted.count >= 2 else { return nil }

    let isInterpolated = word >= first.word && word <= last.word
    let overshoot = max(first.word - word, word - last.word)
    guard isInterpolated || overshoot <= maximumExtrapolationWords else { return nil }

    let pair = bracket(word, in: sorted)
    let words = pair.after.word - pair.before.word
    guard words >= minimumSpanWords || isInterpolated else { return nil }
    guard words > 0 else { return nil }

    let rate = (pair.after.time - pair.before.time) / Double(words)
    guard rate > 0 else { return nil }

    return Estimate(
      time: max(0, pair.before.time + Double(word - pair.before.word) * rate),
      isInterpolated: isInterpolated
    )
  }

  private static func bracket(_ word: Int, in sorted: [Anchor]) -> (before: Anchor, after: Anchor) {
    if word <= sorted[0].word { return (sorted[0], sorted[1]) }
    if word >= sorted[sorted.count - 1].word {
      return (sorted[sorted.count - 2], sorted[sorted.count - 1])
    }

    for position in 1..<sorted.count where word < sorted[position].word {
      return (sorted[position - 1], sorted[position])
    }

    return (sorted[sorted.count - 2], sorted[sorted.count - 1])
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
