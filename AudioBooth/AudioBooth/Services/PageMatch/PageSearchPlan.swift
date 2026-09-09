import Foundation

nonisolated enum PageSearchPlan {
  static let estimateRadius: TimeInterval = 120

  static func windows(
    for page: ScannedPage,
    chapters: [AudioChapter],
    duration: TimeInterval,
    playhead: TimeInterval?,
    estimatedTime: TimeInterval? = nil,
    ebookEstimates: [AudioPositionEstimator.Estimate] = []
  ) -> [AudioSearchWindow] {
    var windows: [AudioSearchWindow] = []
    var used: Set<Int> = []

    func surround(_ time: TimeInterval, radius: TimeInterval, origin: AudioSearchWindow.Origin) {
      guard duration > 0 else { return }
      let lower = max(0, time - radius)
      let upper = min(duration, time + radius)
      guard upper > lower else { return }
      windows.append(
        AudioSearchWindow(
          range: lower...upper,
          chapterTitle: chapters.first { $0.contains(time) }?.title,
          origin: origin
        )
      )
    }

    for estimate in ebookEstimates {
      surround(estimate.time, radius: estimate.confidence.searchRadius, origin: .ebook)
    }

    if let estimatedTime {
      surround(estimatedTime, radius: estimateRadius, origin: .pageNumber)
    }

    guard !chapters.isEmpty else {
      guard duration > 0 else { return windows }
      windows.append(
        AudioSearchWindow(range: 0...duration, chapterTitle: nil, origin: .currentChapter)
      )
      return windows
    }

    func append(_ position: Int, _ origin: AudioSearchWindow.Origin) {
      guard chapters.indices.contains(position), used.insert(position).inserted else { return }
      let chapter = chapters[position]
      windows.append(
        AudioSearchWindow(
          range: chapter.start...max(chapter.start, chapter.end),
          chapterTitle: chapter.title,
          origin: origin
        )
        .clamped(to: duration)
      )
    }

    if let header = page.header,
      let matched = ChapterTitleMatcher.index(matching: header, in: chapters)
    {
      append(matched, .chapterHeader)
    }

    let centre = centre(in: chapters, estimates: ebookEstimates, playhead: playhead)
    append(centre, .currentChapter)

    guard !ebookEstimates.contains(where: { $0.confidence != .low }) else { return windows }

    for position in chapters.indices where position > centre {
      append(position, .nextChapters)
    }
    for position in stride(from: centre - 1, through: 0, by: -1) {
      append(position, .earlierChapters)
    }

    return windows
  }

  private static func centre(
    in chapters: [AudioChapter],
    estimates: [AudioPositionEstimator.Estimate],
    playhead: TimeInterval?
  ) -> Int {
    let best =
      estimates.first { $0.confidence == .high }
      ?? estimates.first { $0.confidence == .medium }

    if let best, let position = chapters.firstIndex(where: { $0.contains(best.time) }) {
      return position
    }

    return playhead.flatMap { time in chapters.firstIndex { $0.contains(time) } } ?? 0
  }
}
