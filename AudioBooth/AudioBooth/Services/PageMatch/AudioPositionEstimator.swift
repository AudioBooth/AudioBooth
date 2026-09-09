import Foundation

nonisolated enum AudioPositionEstimator {
  struct Estimate: Sendable {
    let time: TimeInterval
    let confidence: SectionChapterMap.Confidence
  }

  private static let candidateSpacing: TimeInterval = 45

  static func estimates(
    forWord word: Int,
    map: SectionChapterMap,
    chapters: [AudioChapter],
    duration: TimeInterval,
    totalWords: Int,
    anchored: BookPositionAnchors.Estimate? = nil
  ) -> [Estimate] {
    guard duration > 0 else { return [] }

    var estimates: [Estimate] = []

    func append(_ time: TimeInterval, _ confidence: SectionChapterMap.Confidence) {
      let clamped = min(max(0, time), max(0, duration - 1))
      guard !estimates.contains(where: { abs($0.time - clamped) < candidateSpacing }) else { return }
      estimates.append(Estimate(time: clamped, confidence: confidence))
    }

    if let anchored {
      append(anchored.time, anchored.isInterpolated ? .high : .medium)
    }

    if let mapped = map.time(forWord: word) {
      let confidence = map.confidence(forWord: word)
      append(mapped, confidence)

      if confidence != .high {
        for neighbour in neighbours(of: mapped, in: chapters) {
          append(neighbour, confidence)
        }
      }
    }

    if totalWords > 0 {
      let fraction = min(1, max(0, Double(word) / Double(totalWords)))
      append(fraction * duration, .low)
    }

    return estimates
  }

  private static func neighbours(
    of time: TimeInterval,
    in chapters: [AudioChapter]
  ) -> [TimeInterval] {
    guard let position = chapters.firstIndex(where: { $0.contains(time) }) else { return [] }

    let chapter = chapters[position]
    let fraction = chapter.duration > 0 ? (time - chapter.start) / chapter.duration : 0

    return [position + 1, position - 1]
      .filter { chapters.indices.contains($0) }
      .map { chapters[$0].start + fraction * chapters[$0].duration }
  }
}
