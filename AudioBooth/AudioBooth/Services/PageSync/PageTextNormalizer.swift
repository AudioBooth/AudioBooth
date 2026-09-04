import Foundation

/// Text normalization shared by the OCR output, the ebook text and the speech transcript so
/// they can be compared word by word regardless of casing, accents or punctuation.
nonisolated enum PageTextNormalizer {
  static func normalize(_ text: String) -> String {
    let folded = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil
    )

    var result = ""
    result.reserveCapacity(folded.utf8.count)
    var lastWasSpace = true

    for scalar in folded.unicodeScalars {
      let properties = scalar.properties
      if properties.isAlphabetic || properties.numericType != nil {
        result.unicodeScalars.append(scalar)
        lastWasSpace = false
      } else if !lastWasSpace {
        result.append(" ")
        lastWasSpace = true
      }
    }

    while result.hasSuffix(" ") {
      result.removeLast()
    }

    return result
  }

  static func tokens(_ text: String) -> [String] {
    normalize(text).split(separator: " ").map(String.init)
  }

  /// Joins OCR lines into a single paragraph, repairing words hyphenated across line breaks.
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
