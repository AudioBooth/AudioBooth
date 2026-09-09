import Foundation
import ReadiumShared

nonisolated struct BookSections: Sendable {
  struct Section: Sendable {
    let href: String
    var title: String?
    let range: Range<Int>

    var length: Int { range.count }
  }

  let sections: [Section]

  static func build(from index: BookTextIndex, publication: Publication) async -> BookSections {
    var sections: [Section] = []
    var currentHref: String?
    var start = 0

    for (position, entry) in index.words.entries.enumerated() {
      guard index.sentences.indices.contains(entry.sentence) else { continue }
      let href = normalize(index.sentences[entry.sentence].locator.href.string)

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

    if case .success(let contents) = await publication.tableOfContents() {
      let entries = flatten(contents)
      for position in sections.indices where sections[position].title == nil {
        let href = sections[position].href
        let match =
          entries.first { $0.href == href }
          ?? entries.first { $0.href.hasSuffix(href) || href.hasSuffix($0.href) }
        sections[position].title = match?.title
      }
    }

    return BookSections(sections: sections)
  }

  private static func flatten(_ links: [Link]) -> [(href: String, title: String?)] {
    links.flatMap { link in
      [(normalize(link.href), link.title)] + flatten(link.children)
    }
  }

  private static func normalize(_ href: String) -> String {
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
