import Foundation

nonisolated struct NarrationTimeline: Sendable {
  struct Entry: Sendable, Equatable {
    let bookWord: Int
    let start: TimeInterval
  }

  private(set) var entries: [Entry] = []

  private static let secondsToHoldPastLastWord: TimeInterval = 5
  private static let longestGapWorthInterpolating: TimeInterval = 10

  var isEmpty: Bool { entries.isEmpty }

  mutating func append(bookWord: Int, at start: TimeInterval) {
    guard start > (entries.last?.start ?? -.greatestFiniteMagnitude) else { return }
    entries.append(Entry(bookWord: bookWord, start: start))
  }

  mutating func removeFrom(_ time: TimeInterval) {
    entries.removeAll { $0.start >= time }
  }

  mutating func removeAll() {
    entries.removeAll()
  }

  func covers(_ time: TimeInterval) -> Bool {
    guard let first = entries.first, let last = entries.last,
      (first.start...last.start).contains(time),
      let index = lastIndex(atOrBefore: time)
    else {
      return false
    }

    guard let next = entries[safe: index + 1] else { return true }
    return next.start - entries[index].start <= Self.longestGapWorthInterpolating
  }

  func bookWord(at time: TimeInterval) -> Int? {
    guard let index = lastIndex(atOrBefore: time) else { return nil }
    let current = entries[index]

    guard let next = entries[safe: index + 1] else {
      return hasLapsed(since: current.start, at: time) ? nil : current.bookWord
    }

    guard next.start - current.start <= Self.longestGapWorthInterpolating else {
      return hasLapsed(since: current.start, at: time) ? nil : current.bookWord
    }

    return interpolate(from: current, to: next, at: time)
  }

  private func hasLapsed(since start: TimeInterval, at time: TimeInterval) -> Bool {
    time - start >= Self.secondsToHoldPastLastWord
  }

  private func interpolate(from current: Entry, to next: Entry, at time: TimeInterval) -> Int {
    let elapsed = next.start - current.start
    let wordsSpanned = next.bookWord - current.bookWord
    guard elapsed > 0.01, wordsSpanned > 1 else { return current.bookWord }

    let fraction = ((time - current.start) / elapsed).clamped(to: 0...1)
    return current.bookWord + Int((Double(wordsSpanned) * fraction).rounded(.down))
  }

  private func lastIndex(atOrBefore time: TimeInterval) -> Int? {
    var low = 0
    var high = entries.count - 1
    var match: Int?

    while low <= high {
      let middle = low + (high - low) / 2
      if entries[middle].start <= time {
        match = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }

    return match
  }
}

nonisolated private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

nonisolated private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
