import Foundation
import Logging

/// Finds where a word of the book is spoken in the audiobook, by transcribing the audio around
/// candidate positions and aligning the transcript with the book text.
///
/// Reuses Read Along's transcriber and aligner. The first aligned chunk also reveals how far the
/// narration is from the text estimate, so the search usually jumps straight to the page instead
/// of checking every candidate.
@available(iOS 26.0, *)
nonisolated enum PageLocator {
  struct Located: Sendable {
    let time: TimeInterval
    let bookWord: Int
    let score: Double
  }

  /// Transcribed words aligned in one go.
  private static let chunkSize = 40
  /// Aligned words this close to the target count as the page.
  private static let targetToleranceWords = 30
  /// Keep listening this long past a window when an alignment is close to the target.
  private static let extensionSeconds: TimeInterval = 60
  private static let minimumScore = 0.55

  static func locate(
    pageWord: Int,
    candidates: [AudioPositionEstimator.Estimate],
    index: BookTextIndex,
    source: NarrationSource,
    locale: Locale,
    duration: TimeInterval,
    onProgress: @escaping @Sendable (String) -> Void
  ) async throws -> Located? {
    guard !candidates.isEmpty, !index.isEmpty else { return nil }

    let aligner = TranscriptAligner(words: index.words)
    let transcriber = NarrationTranscriber(locale: locale, source: source)
    let wordsPerSecond = max(0.5, Double(index.words.count) / max(1, duration))
    var queue = candidates
    var visited: [ClosedRange<TimeInterval>] = []
    var attempts = 0

    while !queue.isEmpty, attempts < candidates.count + 2 {
      let candidate = queue.removeFirst()
      attempts += 1
      let window = max(0, candidate.time - candidate.searchRadius)...(candidate.time + candidate.searchRadius)
      guard !visited.contains(where: { $0.contains(candidate.time) }) else { continue }
      visited.append(window)
      onProgress(progressMessage(for: candidate, attempt: attempts))

      let outcome = try await listen(
        window: window,
        pageWord: pageWord,
        aligner: aligner,
        transcriber: transcriber
      )

      switch outcome {
      case .found(let located):
        return located
      case .heard(let bookWord, let time):
        // We know where the narration is at `time`; jump the difference in words.
        let jump = time + Double(pageWord - bookWord) / wordsPerSecond
        AppLogger.viewModel.info(
          "Page Sync: heard word \(bookWord) at \(Int(time))s, page word is \(pageWord); jumping to \(Int(jump))s"
        )
        let estimate = AudioPositionEstimator.Estimate(time: jump, chapterTitle: nil, method: .calibrated)
        if !visited.contains(where: { $0.contains(jump) }) {
          queue.insert(estimate, at: 0)
        }
      case .nothing:
        continue
      }
    }

    return nil
  }

  private enum Outcome {
    case found(Located)
    case heard(bookWord: Int, time: TimeInterval)
    case nothing
  }

  private static func listen(
    window: ClosedRange<TimeInterval>,
    pageWord: Int,
    aligner: TranscriptAligner,
    transcriber: NarrationTranscriber
  ) async throws -> Outcome {
    var deadline = window.upperBound
    var chunk: [TranscribedWord] = []
    var heard: (bookWord: Int, time: TimeInterval)?
    var expectedStart: Int?
    /// Closest aligned words spoken before and at-or-after the page's first word.
    var before: (bookWord: Int, time: TimeInterval)?
    var after: (bookWord: Int, time: TimeInterval)?
    let started = Date()
    var transcribed = 0

    let windowStart = window.lowerBound
    let stream = await MainActor.run {
      transcriber.words(from: windowStart) { deadline }
    }
    for try await word in stream {
      try Task.checkCancellation()
      transcribed += 1
      if word.start > deadline { break }
      chunk.append(word)
      guard chunk.count >= chunkSize else { continue }

      let query = chunk.map(\.normalized)
      if let alignment = aligner.align(query: query, expectedStart: expectedStart),
        let first = alignment.firstBookWord
      {
        expectedStart = alignment.expectedStartOfNextWindow(stride: chunkSize)
        if heard == nil {
          heard = (first, chunk[alignment.words[0].queryIndex].start)
        }

        for aligned in alignment.words {
          let time = chunk[aligned.queryIndex].start
          if aligned.bookWord < pageWord {
            if before == nil || aligned.bookWord > before!.bookWord {
              before = (aligned.bookWord, time)
            }
          } else if after == nil || aligned.bookWord < after!.bookWord {
            after = (aligned.bookWord, time)
          }
        }

        // Only a word spoken at or after the page's first word pins the start. Extrapolating
        // forward from earlier words would cross chapter pauses and announcements and land
        // too early.
        if let after, after.bookWord - pageWord <= targetToleranceWords {
          let time = timeOfPageStart(pageWord: pageWord, after: after, before: before, chunk: chunk)
          AppLogger.viewModel.info(
            "Page Sync: page found at \(String(format: "%.1f", time))s (score \(String(format: "%.2f", alignment.score)), anchor word \(after.bookWord) for page word \(pageWord), \(transcribed) words in \(Int(Date().timeIntervalSince(started)))s)"
          )
          return .found(Located(time: time, bookWord: pageWord, score: alignment.score))
        }

        // The page is just ahead: keep listening a little longer.
        if let last = alignment.lastBookWord, pageWord > last, pageWord - last < 400 {
          deadline = max(deadline, word.start + extensionSeconds)
        }
      }
      chunk.removeAll(keepingCapacity: true)
    }

    AppLogger.viewModel.info(
      "Page Sync: window \(Int(window.lowerBound))s-\(Int(window.upperBound))s: \(transcribed) words, page not in it"
    )
    if let heard {
      return .heard(bookWord: heard.bookWord, time: heard.time)
    }
    return .nothing
  }

  /// Seconds to start before the first word so it is not clipped.
  private static let leadSeconds: TimeInterval = 0.75

  /// Time of the page's first word, backed up from the closest word spoken at or after it using
  /// the local speaking rate, and never earlier than the last word known to come before it.
  private static func timeOfPageStart(
    pageWord: Int,
    after: (bookWord: Int, time: TimeInterval),
    before: (bookWord: Int, time: TimeInterval)?,
    chunk: [TranscribedWord]
  ) -> TimeInterval {
    var time = after.time
    if after.bookWord != pageWord {
      let spoken = chunk.count > 1 ? (chunk[chunk.count - 1].end - chunk[0].start) / Double(chunk.count) : 0.4
      let secondsPerWord = spoken > 0 ? spoken : 0.4
      time -= Double(after.bookWord - pageWord) * secondsPerWord
    }
    time -= leadSeconds
    if let before {
      time = max(time, before.time + 0.2)
    }
    return max(0, time)
  }

  private static func progressMessage(for candidate: AudioPositionEstimator.Estimate, attempt: Int) -> String {
    if attempt == 1 {
      return String(localized: "Listening to the audio…")
    }
    if let title = candidate.chapterTitle {
      return String(localized: "Not there yet. Checking \(title)…")
    }
    return String(localized: "Not there yet. Checking another spot…")
  }
}
