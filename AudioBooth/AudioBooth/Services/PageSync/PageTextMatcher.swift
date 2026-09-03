import Foundation

/// Locates the text of a scanned page inside an `EbookTextIndex`.
///
/// The OCR output is sliced into short word windows that are searched verbatim in the ebook.
/// Several windows agreeing on the same region of the book give a robust match even when OCR
/// mangles part of the page.
nonisolated enum PageTextMatcher {
  struct Match: Sendable {
    /// UTF-8 offset in `EbookTextIndex.text` where the scanned page approximately starts.
    let offset: Int
    let matchedWindows: Int
    let totalWindows: Int

    var confidence: Double {
      guard totalWindows > 0 else { return 0 }
      return Double(matchedWindows) / Double(totalWindows)
    }
  }

  private static let windowSizes = [8, 6, 5, 4]
  private static let clusterTolerance = 600

  /// Converts OCR lines into normalized tokens, dropping running headers and page numbers.
  static func pageTokens(from lines: [String]) -> [String] {
    var lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    func looksLikeFurniture(_ line: String) -> Bool {
      let tokens = PageTextNormalizer.tokens(line)
      if tokens.isEmpty { return true }
      if tokens.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return true }
      return tokens.count <= 3
    }

    if lines.count > 2, let first = lines.first, looksLikeFurniture(first) {
      lines.removeFirst()
    }
    if lines.count > 2, let last = lines.last, looksLikeFurniture(last) {
      lines.removeLast()
    }

    return PageTextNormalizer.tokens(PageTextNormalizer.joinLines(lines))
  }

  static func match(tokens: [String], in index: EbookTextIndex) -> Match? {
    guard tokens.count >= 4, !index.isEmpty else { return nil }

    var prefixLengths: [Int] = [0]
    prefixLengths.reserveCapacity(tokens.count + 1)
    for token in tokens {
      prefixLengths.append(prefixLengths[prefixLengths.count - 1] + token.utf8.count + 1)
    }

    for windowSize in windowSizes where tokens.count >= windowSize {
      var hits: [(window: Int, pageStart: Int)] = []
      var totalWindows = 0
      let step = max(1, windowSize / 2)

      var start = 0
      while start + windowSize <= tokens.count {
        totalWindows += 1
        let phrase = " " + tokens[start..<start + windowSize].joined(separator: " ") + " "
        for offset in occurrences(of: phrase, in: index.text, limit: 8) {
          hits.append((start, offset - prefixLengths[start]))
        }
        start += step
      }

      if let match = bestCluster(hits, totalWindows: totalWindows, windowSize: windowSize) {
        return match
      }
    }

    return nil
  }

  private static func occurrences(of phrase: String, in text: String, limit: Int) -> [Int] {
    var results: [Int] = []
    var searchRange = text.startIndex..<text.endIndex

    while results.count < limit,
      let range = text.range(of: phrase, options: [], range: searchRange)
    {
      results.append(text.utf8.distance(from: text.startIndex, to: range.lowerBound))
      searchRange = text.index(after: range.lowerBound)..<text.endIndex
    }

    return results
  }

  private static func bestCluster(
    _ hits: [(window: Int, pageStart: Int)],
    totalWindows: Int,
    windowSize: Int
  ) -> Match? {
    guard !hits.isEmpty else { return nil }

    let sorted = hits.sorted { $0.pageStart < $1.pageStart }
    var best: (windows: Set<Int>, starts: [Int])?

    for (anchorIndex, anchor) in sorted.enumerated() {
      var windows: Set<Int> = []
      var starts: [Int] = []
      for hit in sorted[anchorIndex...] {
        guard hit.pageStart - anchor.pageStart <= clusterTolerance else { break }
        windows.insert(hit.window)
        starts.append(hit.pageStart)
      }
      if windows.count > (best?.windows.count ?? 0) {
        best = (windows, starts)
      }
    }

    guard let best else { return nil }

    // Two agreeing windows, or a single long and unique phrase, is enough to trust the match.
    let isUniqueLongPhrase = best.windows.count == 1 && windowSize >= 6 && hits.count == 1
    guard best.windows.count >= 2 || isUniqueLongPhrase else { return nil }

    let starts = best.starts.sorted()
    let median = starts[starts.count / 2]

    return Match(
      offset: max(0, median),
      matchedWindows: best.windows.count,
      totalWindows: totalWindows
    )
  }
}
