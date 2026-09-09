import Foundation
import Logging
import ReadiumShared

enum PositionSyncCheck {
  @available(iOS 26.0, *)
  static func measure(
    context: BookSyncContext,
    audioTime: TimeInterval
  ) async -> PositionAlignment? {
    guard let url = context.ebookURL, let source = context.source else { return nil }

    let ebook = await EbookTextIndexLoader().load(
      bookID: context.bookID,
      url: url,
      chapters: context.chapters,
      duration: context.duration
    )
    guard let ebook, !Task.isCancelled else { return nil }

    let locator = context.ebookLocation.flatMap { try? Locator(jsonString: $0) }
    guard
      let reading = EbookExcerpt.readingWord(
        locator: locator,
        progression: context.ebookProgress,
        index: ebook.index,
        sections: ebook.sections
      )
    else {
      return nil
    }

    if let mismatch = chapterMismatch(
      audioTime: audioTime,
      readingWord: reading,
      chapters: context.chapters,
      ebook: ebook
    ) {
      return mismatch
    }

    let locale: Locale
    do {
      locale = try await ReadAlongAvailability.prepare(preferred: context.locale)
    } catch {
      AppLogger.readAlong.info("Alignment: speech recognition is unavailable: \(error)")
      return nil
    }
    guard !Task.isCancelled else { return nil }

    let alignment = try? await PositionAlignment.measure(
      audioTime: audioTime,
      readingWord: reading,
      expectedNarratorWord: ebook.map.word(forTime: audioTime),
      ebook: ebook,
      source: source,
      locale: locale
    )

    return alignment
  }

  private static func chapterMismatch(
    audioTime: TimeInterval,
    readingWord: Int,
    chapters: [AudioChapter],
    ebook: EbookTextIndexLoader.Loaded
  ) -> PositionAlignment? {
    guard ebook.map.hasMatchedChapters,
      let narratorChapter = chapters.firstIndex(where: { $0.contains(audioTime) }),
      let readingTime = ebook.map.time(forWord: readingWord),
      let readingChapter = chapters.firstIndex(where: { $0.contains(readingTime) }),
      narratorChapter != readingChapter,
      let narratorWord = ebook.map.word(forTime: audioTime),
      abs(narratorWord - readingWord) > PositionAlignment.estimateTolerance
    else {
      return nil
    }

    AppLogger.readAlong.info(
      "Alignment: the narrator is in \(chapters[narratorChapter].title) but you are reading \(chapters[readingChapter].title)"
    )

    return PositionAlignment(
      narratorWord: narratorWord,
      readingWord: readingWord,
      totalWords: ebook.index.words.count,
      isVerified: false
    )
  }
}
