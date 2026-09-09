import Foundation

nonisolated struct AudioSearchWindow: Sendable {
  enum Origin: Sendable {
    case ebook
    case pageNumber
    case chapterHeader
    case currentChapter
    case nextChapters
    case earlierChapters
  }

  static let contiguousLimit: TimeInterval = 300

  let range: ClosedRange<TimeInterval>
  let chapterTitle: String?
  let origin: Origin

  var seconds: TimeInterval { range.upperBound - range.lowerBound }

  var isTight: Bool { seconds <= Self.contiguousLimit }

  func clamped(to duration: TimeInterval) -> AudioSearchWindow {
    let lower = max(0, range.lowerBound)
    let upper = min(max(lower, duration), range.upperBound)
    return AudioSearchWindow(range: lower...max(lower, upper), chapterTitle: chapterTitle, origin: origin)
  }

  func covers(_ other: AudioSearchWindow) -> Bool {
    range.lowerBound <= other.range.lowerBound && range.upperBound >= other.range.upperBound
  }
}
