import Foundation
import ReadiumShared

/// Chapter-level view of a `BookTextIndex`: which words belong to which reading-order
/// resource, with the table of contents title when there is one. Used to project a position in
/// the text onto the audiobook's chapters.
nonisolated struct BookSections: Sendable {
  struct Section: Sendable {
    /// Normalized resource href.
    let href: String
    var title: String?
    /// Word positions in the `BookTextIndex`.
    let range: Range<Int>

    var length: Int { range.count }
  }

  let sections: [Section]
  /// Total number of indexed words.
  let totalLength: Int

  func section(containing word: Int) -> Section? {
    sections.first { $0.range.contains(word) } ?? sections.last
  }

  static func build(from index: BookTextIndex, publication: Publication) async -> BookSections {
    var sections: [Section] = []
    var currentHref: String?
    var start = 0

    for (position, entry) in index.words.entries.enumerated() {
      guard index.sentences.indices.contains(entry.sentence) else { continue }
      let sentence = index.sentences[entry.sentence]
      let href = normalizeHref(sentence.locator.href.string)
      if href != currentHref {
        if let currentHref, position > start {
          sections.append(Section(href: currentHref, range: start..<position))
        }
        currentHref = href
        start = position
      }
    }
    if let currentHref, index.words.count > start {
      sections.append(Section(href: currentHref, range: start..<index.words.count))
    }

    if case .success(let toc) = await publication.tableOfContents() {
      let entries = flatten(toc)
      for position in sections.indices where sections[position].title == nil {
        let href = sections[position].href
        if let entry = entries.first(where: { $0.href == href })
          ?? entries.first(where: { $0.href.hasSuffix(href) || href.hasSuffix($0.href) })
        {
          sections[position].title = entry.title
        }
      }
    }

    return BookSections(sections: sections, totalLength: index.words.count)
  }

  private static func flatten(_ links: [Link]) -> [(href: String, title: String?)] {
    links.flatMap { link in
      [(normalizeHref(link.href), link.title)] + flatten(link.children)
    }
  }

  private static func normalizeHref(_ href: String) -> String {
    var value = href
    if let fragment = value.firstIndex(of: "#") {
      value = String(value[..<fragment])
    }
    if let query = value.firstIndex(of: "?") {
      value = String(value[..<query])
    }
    value = value.removingPercentEncoding ?? value
    while value.hasPrefix("/") {
      value.removeFirst()
    }
    return value
  }
}

nonisolated extension BookTextIndex {
  /// The book's own words starting at `word`, capped at `wordLimit` words, for showing a match
  /// without the recognition errors of scanned or transcribed text.
  func excerpt(startingAtWord word: Int, wordLimit: Int = 40) -> String {
    guard words.entries.indices.contains(word) else { return "" }
    let entry = words.entries[word]
    var result: [String] = []
    var sentence = entry.sentence
    while result.count < wordLimit, sentences.indices.contains(sentence) {
      let text = sentences[sentence].text
      result += text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      sentence += 1
    }
    let clipped = result.prefix(wordLimit)
    return clipped.joined(separator: " ") + (result.count > wordLimit ? "…" : "")
  }
}
