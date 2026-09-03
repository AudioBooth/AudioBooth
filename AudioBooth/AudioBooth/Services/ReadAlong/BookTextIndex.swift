import Foundation
import ReadiumShared

nonisolated struct BookTextIndex: Sendable {
  struct Sentence: Sendable {
    let locator: Locator
    let text: String
  }

  let sentences: [Sentence]
  let words: NarrationWordIndex

  var isEmpty: Bool { words.isEmpty }

  func wordLocator(forWord position: Int) -> Locator? {
    guard let word = words.entries[safe: position],
      let sentence = sentences[safe: word.sentence]
    else {
      return nil
    }

    let start = String.Index(utf16Offset: word.startOffsetInSentence, in: sentence.text)
    let end = String.Index(utf16Offset: word.endOffsetInSentence, in: sentence.text)
    guard start < end, end <= sentence.text.endIndex else { return sentence.locator }

    return sentence.locator.copy(text: { $0 = $0[start..<end] })
  }

  func sentenceLocator(forWord position: Int) -> Locator? {
    guard let word = words.entries[safe: position] else { return nil }
    return sentences[safe: word.sentence]?.locator
  }
}

nonisolated extension BookTextIndex {
  static func build(
    publication: Publication,
    progress: @Sendable @escaping (Double) -> Void = { _ in }
  ) async -> BookTextIndex {
    guard let content = publication.content(from: nil) else { return .empty }

    let splitIntoSentences = makeDefaultTextTokenizer(
      unit: .sentence,
      language: publication.metadata.language
    )
    let reporter = SpineProgressReporter(readingOrder: publication.readingOrder, report: progress)

    var sentences: [Sentence] = []
    var entries: [NarrationWordIndex.Entry] = []

    for await element in content.sequence() {
      guard !Task.isCancelled else { break }
      reporter.advance(to: element.locator.href)

      guard let textElement = element as? TextContentElement else { continue }

      for segment in textElement.segments {
        for range in segment.text.sentenceRanges(using: splitIntoSentences) {
          let text = String(segment.text[range])
          let indexedWords = ReadAlongText.normalizedWordsWithRanges(in: text)
          guard !indexedWords.isEmpty else { continue }

          entries.append(
            contentsOf: indexedWords.map { word, wordRange in
              NarrationWordIndex.Entry(
                normalized: word,
                sentence: sentences.count,
                startOffsetInSentence: wordRange.lowerBound.utf16Offset(in: text),
                endOffsetInSentence: wordRange.upperBound.utf16Offset(in: text)
              )
            }
          )

          sentences.append(
            Sentence(locator: segment.locator.highlighting(range, in: segment.text), text: text)
          )
        }
      }
    }

    progress(1)
    return BookTextIndex(sentences: sentences, words: NarrationWordIndex(entries: entries))
  }

  static var empty: BookTextIndex {
    BookTextIndex(sentences: [], words: NarrationWordIndex(entries: []))
  }
}

nonisolated private final class SpineProgressReporter: @unchecked Sendable {
  private let readingOrder: [ReadiumShared.Link]
  private let report: @Sendable (Double) -> Void
  private var lastReportedIndex = -1

  init(readingOrder: [ReadiumShared.Link], report: @escaping @Sendable (Double) -> Void) {
    self.readingOrder = readingOrder
    self.report = report
  }

  func advance(to href: AnyURL) {
    guard let index = readingOrder.firstIndexWithHREF(href), index != lastReportedIndex else { return }
    lastReportedIndex = index
    report(Double(index) / Double(max(readingOrder.count, 1)))
  }
}

nonisolated private extension String {
  func sentenceRanges(using tokenize: TextTokenizer) -> [Range<String.Index>] {
    (try? tokenize(self)) ?? [startIndex..<endIndex]
  }
}

nonisolated private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

nonisolated private extension Locator {
  static let contextSnippetLength = 50

  func highlighting(_ range: Range<String.Index>, in text: String) -> Locator {
    copy(text: {
      $0 = Locator.Text(
        after: String(text[range.upperBound...].prefix(Self.contextSnippetLength)).nilIfEmpty,
        before: String(text[..<range.lowerBound].suffix(Self.contextSnippetLength)).nilIfEmpty,
        highlight: String(text[range])
      )
    })
  }
}

nonisolated private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
