import Foundation
import Logging

@available(iOS 26.0, *)
nonisolated enum PageLocator {
  struct Located: Sendable {
    let time: TimeInterval
    let score: Double
    let isExact: Bool
    var pageSeconds: TimeInterval?
  }

  struct Guide: Sendable {
    let ebookWords: NarrationWordIndex
    let targetWord: Int
    let wordsPerSecond: Double
  }

  static let sampleSeconds: TimeInterval = 15
  static let extendedSampleSeconds: TimeInterval = 30
  static let minimumSampleWords = 20
  static let sampleInterval: TimeInterval = 90
  static let screenThreshold = 0.5
  static let refineLookBack: TimeInterval = 140
  static let refineLookForward: TimeInterval = 40
  private static let refineOverlapFloor = 0.3
  private static let sampleReadCeiling: TimeInterval = 25
  private static let refineReadCeiling: TimeInterval = 90
  private static let coverageForTiming = 0.8
  private static let alignedPageWords = 60
  private static let pageAlignmentScore = 0.35
  private static let homingAttempts = 4
  private static let homingAlignmentScore = 0.5
  private static let homingMinimumWords = 12
  private static let homingRefineRadius: TimeInterval = 45

  static func locate(
    page: ScannedPage,
    windows: [AudioSearchWindow],
    duration: TimeInterval,
    guide: Guide? = nil,
    source: NarrationSource,
    locale: Locale,
    onProgress: @Sendable @escaping (String) -> Void
  ) async throws -> Located? {
    guard page.isUsable, !windows.isEmpty else { return nil }

    let transcriber = NarrationTranscriber(locale: locale, source: source, priority: .userInitiated)
    let scorer = PageOverlapScorer(pageWords: page.bodyWords)
    var searched: [AudioSearchWindow] = []

    if let guide, let first = windows.first {
      let seed = (first.range.lowerBound + first.range.upperBound) / 2
      if let located = try await home(
        from: seed,
        guide: guide,
        duration: duration,
        page: page,
        scorer: scorer,
        transcriber: transcriber,
        onProgress: onProgress
      ) {
        return located
      }
      try Task.checkCancellation()
    }

    for window in windows {
      try Task.checkCancellation()
      guard !searched.contains(where: { $0.covers(window) }) else { continue }
      searched.append(window)

      onProgress(message(for: window))

      if window.isTight {
        let middle = (window.range.lowerBound + window.range.upperBound) / 2
        if let located = try await refine(
          around: window.range,
          anchoredAt: middle,
          page: page,
          scorer: scorer,
          transcriber: transcriber
        ) {
          return located
        }
        continue
      }

      if let hit = try await screen(
        window: window,
        scorer: scorer,
        transcriber: transcriber
      ) {
        AppLogger.readAlong.info(
          "Page Match: sample at \(Int(hit))s matched the page, refining around it"
        )
        let region = max(0, hit - refineLookBack)...(hit + refineLookForward)
        if let located = try await refine(
          around: region,
          anchoredAt: hit,
          page: page,
          scorer: scorer,
          transcriber: transcriber
        ) {
          return located
        }
      }
    }

    return nil
  }

  private static func home(
    from seed: TimeInterval,
    guide: Guide,
    duration: TimeInterval,
    page: ScannedPage,
    scorer: PageOverlapScorer,
    transcriber: NarrationTranscriber,
    onProgress: @Sendable @escaping (String) -> Void
  ) async throws -> Located? {
    guard guide.wordsPerSecond > 0, duration > 0 else { return nil }

    var aligner = TranscriptAligner(words: guide.ebookWords)
    aligner.minimumScore = homingAlignmentScore

    var time = min(max(0, seed), max(0, duration - 1))
    var visited: [TimeInterval] = []

    for _ in 0..<homingAttempts {
      try Task.checkCancellation()
      guard !visited.contains(where: { abs($0 - time) < refineLookForward }) else { return nil }
      visited.append(time)

      let heard = try await sample(from: time, using: transcriber)
      guard heard.count >= homingMinimumWords else { return nil }
      let words = heard.map(\.normalized)

      if scorer.score(against: words) >= screenThreshold {
        AppLogger.readAlong.info("Page Match: homing sample at \(Int(time))s matched the page")
        return try await refine(
          around: max(0, time - refineLookBack)...(time + refineLookForward),
          anchoredAt: time,
          page: page,
          scorer: scorer,
          transcriber: transcriber
        )
      }

      guard let alignment = aligner.align(query: words, expectedStart: nil),
        let anchor = alignment.words.first
      else {
        AppLogger.readAlong.info(
          "Page Match: the narration at \(Int(time))s could not be placed in the ebook"
        )
        return nil
      }

      let narrated = max(0, anchor.bookWord - anchor.queryIndex)
      let apart = guide.targetWord - narrated
      let corrected = min(max(0, time + Double(apart) / guide.wordsPerSecond), max(0, duration - 1))
      AppLogger.readAlong.info(
        "Page Match: at \(Int(time))s the narrator is at ebook word \(narrated), the page is \(apart) word(s) away at about \(Int(corrected))s"
      )

      if abs(corrected - time) < refineLookForward {
        return try await refine(
          around: max(0, corrected - homingRefineRadius)...(corrected + homingRefineRadius),
          anchoredAt: corrected,
          page: page,
          scorer: scorer,
          transcriber: transcriber
        )
      }

      onProgress(String(localized: "Listening to the audiobook…"))
      time = corrected
    }

    return nil
  }

  private static func screen(
    window: AudioSearchWindow,
    scorer: PageOverlapScorer,
    transcriber: NarrationTranscriber
  ) async throws -> TimeInterval? {
    var start = window.range.lowerBound

    while start < window.range.upperBound {
      try Task.checkCancellation()

      let words = try await sample(from: start, using: transcriber)
      let score = scorer.score(against: words.map(\.normalized))

      let formatted: String = String(format: "%.2f", score)
      let heard: String = words.prefix(10).map(\.normalized).joined(separator: " ")
      AppLogger.readAlong.info(
        "Page Match: sample at \(Int(start))s scored \(formatted) over \(words.count) words: \"\(heard)\""
      )

      if score >= screenThreshold {
        return start
      }

      start += sampleInterval
    }

    return nil
  }

  private static func refine(
    around region: ClosedRange<TimeInterval>,
    anchoredAt anchor: TimeInterval,
    page: ScannedPage,
    scorer: PageOverlapScorer,
    transcriber: NarrationTranscriber
  ) async throws -> Located? {
    let words = try await transcribe(
      from: region.lowerBound,
      seconds: region.upperBound - region.lowerBound,
      using: transcriber
    )

    let transcript = TranscriptIndex(words: words)
    guard !transcript.isEmpty else { return nil }

    let score = scorer.score(against: words.map(\.normalized))
    guard score >= refineOverlapFloor else { return nil }

    let query = Array(page.bodyWords.prefix(alignedPageWords))
    var aligner = TranscriptAligner(words: transcript.index)
    aligner.minimumScore = pageAlignmentScore

    guard let alignment = aligner.align(query: query, expectedStart: nil),
      let time = transcript.time(ofPageStartMatching: alignment)
    else {
      let formatted: String = String(format: "%.2f", score)
      AppLogger.readAlong.info(
        "Page Match: region \(Int(region.lowerBound))s scored \(formatted) over \(words.count) heard words but \(query.count) page words would not align"
      )
      return Located(time: anchor, score: score, isExact: false)
    }

    let pageSeconds = narratedLength(
      of: page,
      queryLength: query.count,
      alignment: alignment,
      transcript: transcript
    )
    let overlap: String = String(format: "%.2f", score)
    let quality: String = String(format: "%.2f", alignment.score)
    let length: String = pageSeconds.map { "\(Int($0))s" } ?? "length unknown"
    AppLogger.readAlong.info(
      "Page Match: page starts at \(Int(time))s (overlap \(overlap), alignment \(quality), page \(length))"
    )
    return Located(time: time, score: score, isExact: true, pageSeconds: pageSeconds)
  }

  private static func sample(
    from start: TimeInterval,
    using transcriber: NarrationTranscriber
  ) async throws -> [TranscribedWord] {
    let shortDeadline = start + sampleSeconds
    let longDeadline = start + extendedSampleSeconds
    var words: [TranscribedWord] = []

    let started = Date()
    let stream = await MainActor.run { transcriber.words(from: start) { .infinity } }

    for try await word in stream {
      try Task.checkCancellation()
      if word.start > longDeadline { break }
      if Date().timeIntervalSince(started) > sampleReadCeiling { break }
      if word.start > shortDeadline, words.count >= minimumSampleWords { break }
      words.append(word)
    }

    return words
  }

  private static func narratedLength(
    of page: ScannedPage,
    queryLength: Int,
    alignment: TranscriptAligner.Alignment,
    transcript: TranscriptIndex
  ) -> TimeInterval? {
    guard let first = alignment.words.first, let last = alignment.words.last,
      let startTime = transcript.time(atWord: first.bookWord),
      let endTime = transcript.time(atWord: last.bookWord)
    else {
      return nil
    }

    let aligned = last.queryIndex - first.queryIndex
    let covered = Double(aligned) / Double(max(1, queryLength))
    guard aligned > 0, covered >= coverageForTiming, endTime > startTime else { return nil }

    return (endTime - startTime) * Double(page.bodyWords.count) / Double(aligned)
  }

  private static func transcribe(
    from start: TimeInterval,
    seconds: TimeInterval,
    using transcriber: NarrationTranscriber
  ) async throws -> [TranscribedWord] {
    let deadline = start + seconds
    let ceiling = max(refineReadCeiling, seconds)
    let started = Date()
    var words: [TranscribedWord] = []

    let stream = await MainActor.run { transcriber.words(from: start) { .infinity } }

    for try await word in stream {
      try Task.checkCancellation()
      if word.start > deadline { break }
      if Date().timeIntervalSince(started) > ceiling { break }
      words.append(word)
    }

    return words
  }

  private static func message(for window: AudioSearchWindow) -> String {
    guard let title = window.chapterTitle else {
      return String(localized: "Listening to the audiobook…")
    }

    switch window.origin {
    case .ebook, .pageNumber:
      return String(localized: "Listening around \(title)…")
    case .chapterHeader, .currentChapter:
      return String(localized: "Listening to \(title)…")
    case .nextChapters, .earlierChapters:
      return String(localized: "Not there yet. Checking \(title)…")
    }
  }
}
