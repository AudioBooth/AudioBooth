import Foundation

nonisolated enum ChapterTitleMatcher {
  private static let minimumComparableLength = 4

  static func index(matching heading: String, in chapters: [AudioChapter]) -> Int? {
    let wanted = normalize(heading)
    guard !wanted.isEmpty, !chapters.isEmpty else { return nil }

    let titles = chapters.map { normalize($0.title) }

    if let exact = titles.firstIndex(of: wanted) {
      return exact
    }

    if wanted.count >= minimumComparableLength {
      let containing = titles.indices.filter {
        titles[$0].contains(wanted)
          || (titles[$0].count >= minimumComparableLength && wanted.contains(titles[$0]))
      }
      if containing.count == 1 {
        return containing[0]
      }
    }

    guard let number = ChapterNumber.parse(wanted) else { return nil }
    let numbered = titles.indices.filter { ChapterNumber.parse(titles[$0]) == number }
    return numbered.count == 1 ? numbered[0] : nil
  }

  private static func normalize(_ title: String) -> String {
    ReadAlongText.normalizedWords(in: title).joined(separator: " ")
  }
}
