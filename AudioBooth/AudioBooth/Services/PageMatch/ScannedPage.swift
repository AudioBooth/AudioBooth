import Foundation

nonisolated struct ScannedPage: Sendable {
  let bodyWords: [String]
  let header: String?
  let pageNumber: Int?

  private static let furnitureWordLimit = 3
  private static let minimumBodyLines = 2
  private static let leadingFurnitureLines = 2

  static let minimumWords = 40

  var isUsable: Bool { bodyWords.count >= Self.minimumWords }

  static func parse(lines: [String]) -> ScannedPage {
    var remaining =
      lines
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var heading: [String] = []
    var trailing: [String] = []

    while heading.count < leadingFurnitureLines, remaining.count > minimumBodyLines,
      let first = remaining.first, isFurniture(first)
    {
      heading.append(remaining.removeFirst())
    }
    if remaining.count > minimumBodyLines, let last = remaining.last, isFurniture(last) {
      trailing.append(remaining.removeLast())
    }

    return ScannedPage(
      bodyWords: ReadAlongText.normalizedWords(in: joined(remaining)),
      header: title(in: joined(heading)),
      pageNumber: (trailing + heading).compactMap(number).first
    )
  }

  private static func isFurniture(_ line: String) -> Bool {
    let words = ReadAlongText.normalizedWords(in: line)
    if words.isEmpty { return true }
    if words.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return true }
    return words.count <= furnitureWordLimit
  }

  private static func title(in line: String) -> String? {
    let words = ReadAlongText.normalizedWords(in: line)
    let heading = Array(words.drop { $0.allSatisfy(\.isNumber) })
    guard !heading.isEmpty else { return nil }
    return heading.joined(separator: " ")
  }

  private static func number(in line: String) -> Int? {
    let words = ReadAlongText.normalizedWords(in: line)
    guard !words.isEmpty, words.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
    return words.compactMap { Int($0) }.first
  }

  static func joined(_ lines: [String]) -> String {
    var output = ""
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }

      if let last = output.last, "-‐‑".contains(last) {
        output.removeLast()
        output += trimmed
        continue
      }

      if !output.isEmpty {
        output += " "
      }
      output += trimmed
    }
    return output
  }
}
