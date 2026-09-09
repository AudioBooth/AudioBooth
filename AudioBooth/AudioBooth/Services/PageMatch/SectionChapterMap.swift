import Foundation

nonisolated struct SectionChapterMap: Sendable {
  enum Confidence: Sendable {
    case high
    case medium
    case low

    var searchRadius: TimeInterval {
      switch self {
      case .high: 45
      case .medium: 120
      case .low: 240
      }
    }
  }

  struct Anchor: Sendable {
    let word: Int
    let time: TimeInterval
    let isMatched: Bool
  }

  let anchors: [Anchor]

  private static let minimumBodySectionLength = 80
  private static let minimumTimeCoverage = 0.5

  var hasMatchedChapters: Bool { anchors.contains { $0.isMatched } }

  func time(forWord word: Int) -> TimeInterval? {
    guard let (before, after) = bracket(word) else { return nil }

    let words = after.word - before.word
    guard words > 0 else { return before.time }

    let fraction = Double(word - before.word) / Double(words)
    return before.time + fraction * (after.time - before.time)
  }

  func confidence(forWord word: Int) -> Confidence {
    guard let (before, after) = bracket(word) else { return .low }
    guard hasMatchedChapters else { return .low }
    return before.isMatched && after.isMatched ? .high : .medium
  }

  private func bracket(_ word: Int) -> (Anchor, Anchor)? {
    guard anchors.count >= 2 else { return nil }

    if word <= anchors[0].word { return (anchors[0], anchors[1]) }
    if let last = anchors.last, word >= last.word {
      return (anchors[anchors.count - 2], last)
    }

    for position in 1..<anchors.count where word < anchors[position].word {
      return (anchors[position - 1], anchors[position])
    }

    return nil
  }

  static func build(
    sections: BookSections,
    chapters: [AudioChapter],
    duration: TimeInterval
  ) -> SectionChapterMap {
    let body = sections.sections.filter { $0.length >= minimumBodySectionLength }

    guard let first = body.first, let last = body.last, !chapters.isEmpty, duration > 0 else {
      return SectionChapterMap(anchors: [])
    }

    var matched: [Anchor] = []
    var lastChapter = -1

    for section in body {
      guard let title = section.title,
        let chapter = ChapterTitleMatcher.index(matching: title, in: chapters),
        chapter > lastChapter,
        matched.last.map({
          section.range.lowerBound > $0.word && chapters[chapter].start > $0.time
        }) ?? true
      else {
        continue
      }

      matched.append(
        Anchor(word: section.range.lowerBound, time: chapters[chapter].start, isMatched: true)
      )
      lastChapter = chapter
    }

    if !coversEnoughAudio(
      matched,
      bodyWords: last.range.upperBound - first.range.lowerBound,
      duration: duration
    ) {
      matched = []
    }

    var anchors: [Anchor] = []
    let start = Anchor(word: first.range.lowerBound, time: chapters[0].start, isMatched: false)

    if let leading = matched.first, leading.word <= start.word || leading.time <= start.time {
      anchors = matched
    } else {
      anchors = [start] + matched
    }

    let end = max(chapters[chapters.count - 1].end, duration)
    if let trailing = anchors.last, last.range.upperBound > trailing.word, end > trailing.time {
      anchors.append(Anchor(word: last.range.upperBound, time: end, isMatched: false))
    }

    return SectionChapterMap(anchors: anchors)
  }

  private static func coversEnoughAudio(
    _ matched: [Anchor],
    bodyWords: Int,
    duration: TimeInterval
  ) -> Bool {
    guard matched.count >= 2, let first = matched.first, let last = matched.last else { return true }

    let words = Double(last.word - first.word) / Double(max(1, bodyWords))
    let time = (last.time - first.time) / duration

    return time >= minimumTimeCoverage * words
  }
}
