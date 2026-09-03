import API
import Foundation
import Logging
import Models

/// What Page Sync needs to know about the audiobook side of a title: chapters, duration, the
/// local audio for transcription, the language, and the drift measured on earlier scans.
struct PageSyncBookContext {
  let book: Book
  let localBook: LocalBook?
  /// Item providing the ebook text, when different from `book`.
  var ebookBook: Book?

  init(book: Book, localBook: LocalBook?) {
    self.book = book
    self.localBook = localBook ?? (try? LocalBook.fetch(bookID: book.id))
  }

  var audioChapters: [AudioChapter] {
    if let localBook, !localBook.chapters.isEmpty {
      return localBook.orderedChapters.map { AudioChapter(title: $0.title, start: $0.start, end: $0.end) }
    }
    return (book.chapters ?? []).map { AudioChapter(title: $0.title, start: $0.start, end: $0.end) }
  }

  var audioDuration: TimeInterval {
    if let localBook, localBook.duration > 0 {
      return localBook.duration
    }
    return book.duration
  }

  func chapter(containing time: TimeInterval) -> AudioChapter? {
    audioChapters.first { $0.start <= time && time < $0.end }
  }

  /// Downloaded tracks, which is what the transcriber can read. `nil` until the audiobook is
  /// fully downloaded, like Read Along.
  var narrationSource: NarrationSource? {
    guard let localBook else { return nil }
    let tracks = localBook.orderedTracks
    let local = tracks.compactMap { track -> NarrationSource.Track? in
      guard let url = track.localPath else { return nil }
      return NarrationSource.Track(url: url, secondsFromStartOfBook: track.startOffset, duration: track.duration)
    }
    guard !local.isEmpty, local.count == tracks.count else { return nil }
    return NarrationSource(tracks: local)
  }

  // MARK: - Language

  var bookLanguageCode: String? {
    let raw = (localBook?.language ?? book.media.metadata.language ?? ebookBook?.media.metadata.language)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw, !raw.isEmpty else { return nil }

    if raw.contains("-") || raw.contains("_") {
      return raw.replacingOccurrences(of: "_", with: "-")
    }

    // ISO 639 codes, including three-letter ones such as "spa".
    if raw.count <= 3 {
      return Locale.LanguageCode(raw.lowercased()).identifier(.alpha2) ?? raw.lowercased()
    }

    // Some libraries store the language name ("Spanish") instead of a code.
    let english = Locale(identifier: "en")
    return Locale.LanguageCode.isoLanguageCodes.first { code in
      let identifier = code.identifier
      let englishName = english.localizedString(forLanguageCode: identifier)
      let nativeName = Locale(identifier: identifier).localizedString(forLanguageCode: identifier)
      return englishName?.caseInsensitiveCompare(raw) == .orderedSame
        || nativeName?.caseInsensitiveCompare(raw) == .orderedSame
    }?.identifier
  }

  var recognitionLocale: Locale {
    if let bookLanguageCode {
      return Locale(identifier: bookLanguageCode)
    }
    return Locale.current
  }

  var recognitionLanguages: [String] {
    var candidates: [String] = []
    if let bookLanguageCode {
      candidates.append(bookLanguageCode)
    }
    candidates += Locale.preferredLanguages.prefix(2)
    return PageScannerView.supportedLanguages(from: candidates)
  }

  // MARK: - Calibration

  private static let calibrationKey = "pageSyncCalibration"

  /// Measured difference between where the page was heard and where the text estimate put it.
  /// Audiobooks with long credits or a different edition drift consistently.
  var calibration: TimeInterval? {
    (UserDefaults.standard.dictionary(forKey: Self.calibrationKey) as? [String: Double])?[book.id]
  }

  func storeCalibration(_ drift: TimeInterval) {
    var all = (UserDefaults.standard.dictionary(forKey: Self.calibrationKey) as? [String: Double]) ?? [:]
    all[book.id] = drift
    UserDefaults.standard.set(all, forKey: Self.calibrationKey)
    AppLogger.viewModel.info("Page Sync: stored drift \(Int(drift))s for \(book.id)")
  }
}
