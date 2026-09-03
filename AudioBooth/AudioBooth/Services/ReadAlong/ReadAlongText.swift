import Foundation

nonisolated struct TranscribedWord: Sendable, Equatable {
  let text: String
  let normalized: String
  let start: TimeInterval
  let end: TimeInterval
}

nonisolated enum ReadAlongText {
  private static let abbreviationExpansions: [String: String] = [
    "mr": "mister", "mrs": "missus", "ms": "miss", "dr": "doctor",
    "st": "saint", "prof": "professor", "vs": "versus", "etc": "etcetera",
  ]

  static func normalize(_ token: some StringProtocol) -> String {
    let folded = token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    let alphanumerics = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    let stripped = String(String.UnicodeScalarView(alphanumerics))
    return abbreviationExpansions[stripped] ?? stripped
  }

  static func normalizedWords(in text: String) -> [String] {
    text.wordTokens.map(normalize).filter { !$0.isEmpty }
  }

  static func normalizedWordsWithRanges(in text: String) -> [(word: String, range: Range<String.Index>)] {
    text.wordTokens.compactMap { token in
      let word = normalize(token)
      return word.isEmpty ? nil : (word: word, range: token.startIndex..<token.endIndex)
    }
  }
}

nonisolated private extension StringProtocol {
  var wordTokens: [SubSequence] {
    split(whereSeparator: { !$0.isLetter && !$0.isNumber })
  }
}
