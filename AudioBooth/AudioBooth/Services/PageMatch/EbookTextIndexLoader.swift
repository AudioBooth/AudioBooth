import Foundation
import Logging

final class EbookTextIndexLoader {
  struct Indexed: Sendable {
    let index: BookTextIndex
    let sections: BookSections
  }

  struct Loaded: Sendable {
    let index: BookTextIndex
    let sections: BookSections
    let map: SectionChapterMap
  }

  private static var cachedBookID: String?
  private static var cached: Indexed?

  private let publications = EbookPublicationLoader()

  func load(
    bookID: String,
    url: URL,
    chapters: [AudioChapter],
    duration: TimeInterval
  ) async -> Loaded? {
    guard let indexed = await index(bookID: bookID, url: url) else { return nil }

    let map = await Task.detached(priority: .userInitiated) { [indexed] in
      SectionChapterMap.build(
        sections: indexed.sections,
        chapters: chapters,
        duration: duration
      )
    }.value
    AppLogger.readAlong.info(
      "Page Match: mapped the ebook onto \(map.anchors.count) audio anchor(s)"
    )

    return Loaded(index: indexed.index, sections: indexed.sections, map: map)
  }

  private func index(bookID: String, url: URL) async -> Indexed? {
    if Self.cachedBookID == bookID, let cached = Self.cached {
      return cached
    }

    guard let publication = try? await publications.open(at: url) else {
      AppLogger.readAlong.info("Page Match: the ebook for \(bookID) could not be opened")
      return nil
    }

    let started = Date()
    let built = await Task.detached(priority: .userInitiated) { [publication] in
      let index = await BookTextIndex.build(publication: publication)
      guard !index.isEmpty else { return nil as Indexed? }
      let sections = await BookSections.build(from: index, publication: publication)
      return Indexed(index: index, sections: sections)
    }.value

    guard let built else { return nil }
    let elapsed: String = String(format: "%.1f", Date().timeIntervalSince(started))
    AppLogger.readAlong.info(
      "Page Match: indexed the ebook in \(elapsed)s, \(built.index.words.count) words across \(built.sections.sections.count) sections"
    )

    Self.cachedBookID = bookID
    Self.cached = built
    return built
  }
}
