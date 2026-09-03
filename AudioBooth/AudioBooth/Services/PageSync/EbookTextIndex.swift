import Foundation
import ReadiumShared

/// Normalized plain text of an ebook, split by reading-order resource, used to locate a scanned page.
nonisolated struct EbookTextIndex: Sendable {
  struct Section: Sendable {
    /// Normalized resource href, used to pair sections with the table of contents.
    let href: String
    /// Href exactly as Readium reports it, usable to build a `Locator`.
    let rawHref: String
    var title: String?
    /// UTF-8 offsets into `text`.
    let range: Range<Int>

    var length: Int { range.count }
  }

  /// Normalized text (see `PageTextNormalizer`). Always starts and ends with a space so phrases
  /// can be searched with word boundaries.
  let text: String
  let sections: [Section]

  var isEmpty: Bool { sections.isEmpty }
  var totalLength: Int { text.utf8.count }

  func section(containing offset: Int) -> Section? {
    sections.first { $0.range.contains(offset) } ?? sections.last
  }

  static func build(from publication: Publication) async -> EbookTextIndex {
    guard let content = publication.content() else {
      return EbookTextIndex(text: "", sections: [])
    }

    var text = " "
    var sections: [Section] = []
    var currentHref: String?
    var currentRawHref = ""
    var sectionStart = text.utf8.count

    func closeSection() {
      if let currentHref, text.utf8.count > sectionStart {
        sections.append(
          Section(href: currentHref, rawHref: currentRawHref, range: sectionStart..<text.utf8.count)
        )
      }
    }

    for await element in content.sequence() {
      guard let textual = element as? TextualContentElement,
        let raw = textual.text,
        !raw.isEmpty
      else { continue }

      let rawHref = element.locator.href.string
      let href = Self.normalizeHref(rawHref)
      if href != currentHref {
        closeSection()
        currentHref = href
        currentRawHref = rawHref
        sectionStart = text.utf8.count
      }

      let normalized = PageTextNormalizer.normalize(raw)
      guard !normalized.isEmpty else { continue }
      text += normalized
      text += " "
    }
    closeSection()

    if case .success(let toc) = await publication.tableOfContents() {
      let entries = flatten(toc)
      for index in sections.indices where sections[index].title == nil {
        let href = sections[index].href
        if let entry = entries.first(where: { $0.href == href })
          ?? entries.first(where: { $0.href.hasSuffix(href) || href.hasSuffix($0.href) })
        {
          sections[index].title = entry.title
        }
      }
    }

    return EbookTextIndex(text: text, sections: sections)
  }

  private static func flatten(_ links: [Link]) -> [(href: String, title: String?)] {
    links.flatMap { link in
      [(normalizeHref(link.href), link.title)] + flatten(link.children)
    }
  }

  /// Character offset of a reader location (resource href plus progression inside it).
  func offset(forHref href: String, progression: Double?) -> Int? {
    let normalized = Self.normalizeHref(href)
    guard
      let section = sections.first(where: { $0.href == normalized })
        ?? sections.first(where: { $0.href.hasSuffix(normalized) || normalized.hasSuffix($0.href) })
    else { return nil }
    let fraction = min(1, max(0, progression ?? 0))
    return section.range.lowerBound + Int(fraction * Double(section.length))
  }

  /// Up to `count` normalized words starting at `offset`.
  func tokens(from offset: Int, count: Int) -> [String] {
    let utf8 = text.utf8
    guard offset < utf8.count else { return [] }
    let start = utf8.index(utf8.startIndex, offsetBy: max(0, offset))
    let slice = String(decoding: utf8[start...].prefix(count * 12), as: UTF8.self)
    return Array(slice.split(separator: " ").dropFirst().map(String.init).prefix(count))
  }

  static func normalizeHref(_ href: String) -> String {
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
