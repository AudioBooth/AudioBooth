import Foundation

/// Turns the lines read from a printed page into the normalized words used for matching,
/// dropping running headers and page numbers.
nonisolated enum PageWords {
  static func tokens(from lines: [String]) -> [String] {
    var lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    func looksLikeFurniture(_ line: String) -> Bool {
      let words = normalizedWords(in: line)
      if words.isEmpty { return true }
      if words.allSatisfy({ $0.allSatisfy { $0.isNumber } }) { return true }
      return words.count <= 3
    }

    if lines.count > 2, let first = lines.first, looksLikeFurniture(first) {
      lines.removeFirst()
    }
    if lines.count > 2, let last = lines.last, looksLikeFurniture(last) {
      lines.removeLast()
    }

    return normalizedWords(in: joinLines(lines))
  }

  /// Normalized words of a text, using Read Along's normalization so they match its index.
  static func normalizedWords(in text: String) -> [String] {
    ReadAlongText.normalizedWordsWithRanges(in: text).map(\.word)
  }

  /// Joins lines into a paragraph, repairing words hyphenated across line breaks.
  static func joinLines(_ lines: [String]) -> String {
    var output = ""
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if let last = output.last, "-‐‑".contains(last) {
        output.removeLast()
        output += trimmed
      } else {
        if !output.isEmpty {
          output += " "
        }
        output += trimmed
      }
    }
    return output
  }
}
