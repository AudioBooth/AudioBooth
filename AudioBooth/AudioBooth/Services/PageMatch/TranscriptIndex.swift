import Foundation

nonisolated struct TranscriptIndex: Sendable {
  let words: [TranscribedWord]
  let index: NarrationWordIndex

  init(words: [TranscribedWord]) {
    self.words = words
    index = NarrationWordIndex(
      entries: words.map {
        NarrationWordIndex.Entry(
          normalized: $0.normalized,
          sentence: 0,
          startOffsetInSentence: 0,
          endOffsetInSentence: 0
        )
      }
    )
  }

  var isEmpty: Bool { words.isEmpty }

  func time(atWord position: Int) -> TimeInterval? {
    words.indices.contains(position) ? words[position].start : nil
  }

  func time(ofPageStartMatching alignment: TranscriptAligner.Alignment) -> TimeInterval? {
    guard let first = alignment.words.first, let last = alignment.words.last else { return nil }
    guard first.queryIndex > 0 else { return time(atWord: first.bookWord) }

    let querySpan = last.queryIndex - first.queryIndex
    let heardSpan = last.bookWord - first.bookWord
    let heardPerPageWord =
      querySpan > 0 && heardSpan > 0
      ? min(1, Double(heardSpan) / Double(querySpan))
      : 1

    let backwards = Int((Double(first.queryIndex) * heardPerPageWord).rounded())
    let start = max(0, first.bookWord - backwards)
    return time(atWord: start) ?? time(atWord: first.bookWord)
  }
}
