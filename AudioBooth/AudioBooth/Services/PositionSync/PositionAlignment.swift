import Foundation
import Logging

nonisolated struct PositionAlignment: Sendable {
  let narratorWord: Int
  let readingWord: Int
  let totalWords: Int
  let isVerified: Bool

  var wordsApart: Int { narratorWord - readingWord }

  var isAudioAhead: Bool { wordsApart > tolerance }

  var isEbookAhead: Bool { wordsApart < -tolerance }

  private var tolerance: Int { isVerified ? Self.tolerance : Self.estimateTolerance }

  static let tolerance = 600
  static let estimateTolerance = 1500

  func seconds(over duration: TimeInterval) -> TimeInterval {
    guard totalWords > 0, duration > 0 else { return 0 }
    return abs(Double(wordsApart)) * duration / Double(totalWords)
  }

  func pages(over pageCount: Int) -> Int {
    guard totalWords > 0, pageCount > 0 else { return 0 }
    return Int((abs(Double(wordsApart)) * Double(pageCount) / Double(totalWords)).rounded())
  }

  private static let sampleSeconds: TimeInterval = 20
  private static let minimumHeardWords = 12
  private static let alignmentScore = 0.5

  @available(iOS 26.0, *)
  static func measure(
    audioTime: TimeInterval,
    readingWord: Int,
    expectedNarratorWord: Int?,
    ebook: EbookTextIndexLoader.Loaded,
    source: NarrationSource,
    locale: Locale
  ) async throws -> PositionAlignment? {
    let heard = try await NarrationExcerpt.words(
      from: audioTime,
      seconds: sampleSeconds,
      source: source,
      locale: locale
    )

    guard heard.count >= minimumHeardWords else {
      AppLogger.readAlong.info(
        "Alignment: only heard \(heard.count) word(s) at \(Int(audioTime))s, cannot verify"
      )
      return nil
    }

    var aligner = TranscriptAligner(words: ebook.index.words)
    aligner.minimumScore = alignmentScore

    guard
      let alignment = aligner.align(
        query: heard.map(\.normalized),
        expectedStart: expectedNarratorWord
      ),
      let anchor = alignment.words.first
    else {
      AppLogger.readAlong.info("Alignment: the narration could not be placed in the ebook")
      return nil
    }

    let narratorWord = max(0, anchor.bookWord - anchor.queryIndex)
    let quality: String = String(format: "%.2f", alignment.score)
    AppLogger.readAlong.info(
      "Alignment: the narrator is at ebook word \(narratorWord), reading at \(readingWord) (match \(quality))"
    )

    return PositionAlignment(
      narratorWord: narratorWord,
      readingWord: readingWord,
      totalWords: ebook.index.words.count,
      isVerified: true
    )
  }
}
