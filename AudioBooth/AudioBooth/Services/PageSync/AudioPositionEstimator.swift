import Foundation

nonisolated struct AudioChapter: Sendable {
  let title: String
  let start: TimeInterval
  let end: TimeInterval

  var duration: TimeInterval { max(0, end - start) }
}

/// Converts a position in the ebook text into an approximate position in the audiobook.
///
/// Ebook sections are paired with audio chapters (by title, or by index when both have the same
/// count) and the position inside the section is projected proportionally onto the chapter.
/// Without a usable chapter mapping the position is projected onto the whole book.
nonisolated enum AudioPositionEstimator {
  enum Method: Sendable {
    /// Primary estimate corrected with the drift measured on an earlier scan of this book.
    case calibrated
    case chapterTitle
    case chapterIndex
    case neighborChapter
    case proportional
  }

  struct Estimate: Sendable {
    let time: TimeInterval
    let chapterTitle: String?
    let method: Method

    /// Radius used when checking secondary candidates.
    static let neighborRadius: TimeInterval = 120

    /// How far around the estimate the speech refinement should look.
    var searchRadius: TimeInterval {
      switch method {
      case .calibrated: 120
      case .chapterTitle, .chapterIndex: 150
      case .neighborChapter: 120
      case .proportional: 300
      }
    }
  }

  private static let minimumBodySectionLength = 400
  /// Candidates closer than this to an earlier candidate are redundant.
  private static let candidateSpacing: TimeInterval = 90

  static func estimate(
    offset: Int,
    index: EbookTextIndex,
    chapters: [AudioChapter],
    duration: TimeInterval
  ) -> Estimate {
    candidates(offset: offset, index: index, chapters: chapters, duration: duration)[0]
  }

  /// Prepends the primary estimate shifted by a previously measured drift, so a book whose
  /// audio runs consistently ahead of or behind the text estimate is found on the first try.
  static func applyingCalibration(
    _ drift: TimeInterval?,
    to candidates: [Estimate],
    chapters: [AudioChapter],
    duration: TimeInterval
  ) -> [Estimate] {
    guard let drift, let primary = candidates.first, drift.magnitude >= 1 else { return candidates }
    let time = clamp(primary.time + drift, to: duration)
    let chapter = chapters.first { $0.start <= time && time < $0.end }
    let calibrated = Estimate(time: time, chapterTitle: chapter?.title, method: .calibrated)
    return [calibrated] + candidates.filter { abs($0.time - time) >= candidateSpacing }
  }

  /// Positions worth checking against the audio, best guess first.
  ///
  /// After the primary estimate come the same relative position in the next and previous
  /// chapters, which covers off-by-one chapter mappings (front matter, credits, split parts),
  /// and finally the projection onto the whole book.
  static func candidates(
    offset: Int,
    index: EbookTextIndex,
    chapters: [AudioChapter],
    duration: TimeInterval
  ) -> [Estimate] {
    guard duration > 0, let section = index.section(containing: offset) else {
      return [Estimate(time: 0, chapterTitle: nil, method: .proportional)]
    }

    let fraction = min(1, max(0, Double(offset - section.range.lowerBound) / Double(max(1, section.length))))
    let bodySections = index.sections.filter { $0.length >= minimumBodySectionLength }
    let proportional = proportionalEstimate(
      offset: offset,
      index: index,
      bodySections: bodySections,
      chapters: chapters,
      duration: duration
    )

    var result: [Estimate] = []
    func append(_ estimate: Estimate) {
      guard !result.contains(where: { abs($0.time - estimate.time) < candidateSpacing }) else { return }
      result.append(estimate)
    }

    var mappedChapterIndex: Int?
    var method: Method = .proportional
    let sectionFraction = Double(offset) / Double(max(1, index.totalLength))

    if !chapters.isEmpty {
      if let chapterIndex = chapterIndex(
        matchingTitleOf: section,
        in: chapters,
        duration: duration,
        nearFraction: sectionFraction
      ) {
        mappedChapterIndex = chapterIndex
        method = .chapterTitle
      } else if bodySections.count == chapters.count,
        let sectionIndex = bodySections.firstIndex(where: { $0.href == section.href })
      {
        mappedChapterIndex = sectionIndex
        method = .chapterIndex
      } else if let containing = chapters.firstIndex(where: {
        $0.start <= proportional.time && proportional.time < $0.end
      }) {
        // No mapping: still check the chapters around the proportional guess at the same
        // relative position, which is where an off-by-one usually lands.
        mappedChapterIndex = containing
        method = .proportional
      }
    }

    if method == .proportional {
      append(proportional)
    }

    if let mappedChapterIndex {
      let chapter = chapters[mappedChapterIndex]
      append(
        Estimate(
          time: clamp(chapter.start + fraction * chapter.duration, to: duration),
          chapterTitle: chapter.title,
          method: method == .proportional ? .neighborChapter : method
        )
      )

      for neighbor in [mappedChapterIndex + 1, mappedChapterIndex - 1] where chapters.indices.contains(neighbor) {
        let chapter = chapters[neighbor]
        append(
          Estimate(
            time: clamp(chapter.start + fraction * chapter.duration, to: duration),
            chapterTitle: chapter.title,
            method: .neighborChapter
          )
        )
      }
    }

    append(proportional)

    return result
  }

  private static func proportionalEstimate(
    offset: Int,
    index: EbookTextIndex,
    bodySections: [EbookTextIndex.Section],
    chapters: [AudioChapter],
    duration: TimeInterval
  ) -> Estimate {
    let bodyStart = bodySections.first?.range.lowerBound ?? 0
    let bodyEnd = bodySections.last?.range.upperBound ?? index.totalLength
    let bodyLength = max(1, bodyEnd - bodyStart)
    let globalFraction = min(1, max(0, Double(offset - bodyStart) / Double(bodyLength)))
    let time = clamp(globalFraction * duration, to: duration)
    let chapter = chapters.first { $0.start <= time && time < $0.end }

    return Estimate(time: time, chapterTitle: chapter?.title, method: .proportional)
  }

  private static func chapterIndex(
    matchingTitleOf section: EbookTextIndex.Section,
    in chapters: [AudioChapter],
    duration: TimeInterval,
    nearFraction: Double
  ) -> Int? {
    guard let title = section.title else { return nil }
    let sectionTitle = PageTextNormalizer.normalize(title)
    guard !sectionTitle.isEmpty else { return nil }

    let titles = chapters.map { PageTextNormalizer.normalize($0.title) }

    if let exact = titles.firstIndex(of: sectionTitle) {
      return exact
    }

    if sectionTitle.count >= 4 {
      let containing = titles.indices.filter {
        titles[$0].contains(sectionTitle) || (titles[$0].count >= 4 && sectionTitle.contains(titles[$0]))
      }
      if containing.count == 1 {
        return containing[0]
      }
    }

    // "3" in the ebook against "Chapter 3" in the audiobook, or the other way around. Books
    // split in parts restart their numbering, so pick the occurrence closest to where the
    // page sits in the text.
    if let sectionNumber = leadingNumber(in: sectionTitle) {
      let numbered = titles.indices.filter { leadingNumber(in: titles[$0]) == sectionNumber }
      if numbered.count == 1 {
        return numbered[0]
      }
      if numbered.count > 1, duration > 0 {
        return numbered.min {
          abs(chapters[$0].start / duration - nearFraction) < abs(chapters[$1].start / duration - nearFraction)
        }
      }
    }

    return nil
  }

  private static func leadingNumber(in title: String) -> Int? {
    let tokens = title.split(separator: " ")
    for token in tokens.prefix(3) {
      if let number = Int(token) {
        return number
      }
    }
    return nil
  }

  private static func clamp(_ time: TimeInterval, to duration: TimeInterval) -> TimeInterval {
    min(max(0, time), max(0, duration - 1))
  }
}
