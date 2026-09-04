import API
import Foundation
import Logging
import Models

/// Everything Page Sync needs to know about the audiobook side of a title: chapters, duration,
/// where to get the audio from, and which language to recognize.
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

  var audioSources: [SpeechAlignmentRefiner.AudioSource] {
    if let localBook {
      let local = localBook.orderedTracks.compactMap { track -> SpeechAlignmentRefiner.AudioSource? in
        guard let url = track.localPath else { return nil }
        return SpeechAlignmentRefiner.AudioSource(
          url: url,
          headers: [:],
          startOffset: track.startOffset,
          duration: track.duration
        )
      }
      if !local.isEmpty {
        return local
      }
    }

    guard let serverURL = Audiobookshelf.shared.serverURL,
      let server = Audiobookshelf.shared.authentication.server
    else { return [] }

    // Tracks do not carry the file inode, so pair them with the item's audio files by name.
    let audioFiles = (book.libraryFiles ?? []).filter { $0.fileType == .audio }
    let tracks = book.media.tracks ?? []

    return tracks.compactMap { track in
      let ino =
        track.ino
        ?? audioFiles.first { $0.metadata.filename == track.metadata?.filename }?.ino
        ?? (tracks.count == 1 && audioFiles.count == 1 ? audioFiles[0].ino : nil)
      guard let ino else {
        AppLogger.viewModel.warning("Page Sync: no library file for track \(track.index)")
        return nil
      }
      var url = serverURL.appendingPathComponent("api/items/\(book.id)/file/\(ino)")
      url.append(queryItems: [URLQueryItem(name: "token", value: Self.queryToken(for: server.token))])
      return SpeechAlignmentRefiner.AudioSource(
        url: url,
        headers: server.customHeaders,
        startOffset: track.startOffset,
        duration: track.duration
      )
    }
  }

  private static func queryToken(for credentials: Credentials) -> String {
    switch credentials {
    case .legacy(let token):
      token
    case .bearer(let accessToken, _, _, _):
      accessToken
    case .apiKey(let key):
      key
    }
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
