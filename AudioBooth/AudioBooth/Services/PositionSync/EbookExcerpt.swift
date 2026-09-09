import Foundation
import ReadiumShared

nonisolated enum EbookExcerpt {
  struct Excerpt: Sendable {
    let word: Int
    let page: ScannedPage
    let isSectionStart: Bool
  }

  private static let excerptWords = 80

  static func at(
    locator: Locator,
    index: BookTextIndex,
    sections: BookSections
  ) -> Excerpt? {
    guard let placed = place(locator, in: sections, totalWords: index.words.count) else {
      return nil
    }
    return excerpt(startingAt: placed.word, notBefore: placed.sectionStart, index: index)
  }

  static func at(progression: Double, index: BookTextIndex) -> Excerpt? {
    let clamped = min(1, max(0, progression))
    return excerpt(
      startingAt: Int(clamped * Double(index.words.count)),
      notBefore: 0,
      index: index
    )
  }

  private static func excerpt(
    startingAt word: Int,
    notBefore sectionStart: Int,
    index: BookTextIndex
  ) -> Excerpt? {
    let total = index.words.count
    guard total >= excerptWords else { return nil }

    let anchored = max(sectionStart, sentenceStart(at: word, in: index))
    let start = min(max(0, anchored), total - excerptWords)
    let body = (start..<start + excerptWords).map { index.words[$0].normalized }
    let page = ScannedPage(bodyWords: body, header: nil, pageNumber: nil)
    guard page.isUsable else { return nil }

    return Excerpt(word: start, page: page, isSectionStart: start == sectionStart)
  }

  private static func sentenceStart(at word: Int, in index: BookTextIndex) -> Int {
    let total = index.words.count
    guard total > 0 else { return 0 }

    var position = min(max(0, word), total - 1)
    let sentence = index.words[position].sentence

    while position > 0, index.words[position - 1].sentence == sentence {
      position -= 1
    }

    return position
  }

  static func readingWord(
    locator: Locator?,
    progression: Double?,
    index: BookTextIndex,
    sections: BookSections
  ) -> Int? {
    if let locator,
      let placed = place(locator, in: sections, totalWords: index.words.count)
    {
      return placed.word
    }

    guard let progression, progression > 0 else { return nil }
    return Int(min(1, max(0, progression)) * Double(index.words.count))
  }

  private static func place(
    _ locator: Locator,
    in sections: BookSections,
    totalWords: Int
  ) -> (word: Int, sectionStart: Int)? {
    if let progression = locator.locations.progression,
      let section = sections.section(forHref: locator.href.string)
    {
      let clamped = min(1, max(0, progression))
      return (
        section.range.lowerBound + Int(clamped * Double(section.length)),
        section.range.lowerBound
      )
    }

    guard let total = locator.locations.totalProgression else { return nil }
    return (Int(min(1, max(0, total)) * Double(totalWords)), 0)
  }
}
