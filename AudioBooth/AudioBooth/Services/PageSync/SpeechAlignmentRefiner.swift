import AVFoundation
import Foundation
import Logging
import Speech

/// Sharpens an approximate audio position by transcribing the audio around it and aligning the
/// transcript with the words read from the scanned page.
nonisolated enum SpeechAlignmentRefiner {
  struct AudioSource: Sendable {
    let url: URL
    let headers: [String: String]
    /// Absolute position of the start of this file in the whole audiobook.
    let startOffset: TimeInterval
    let duration: TimeInterval

    var endOffset: TimeInterval { startOffset + duration }
  }

  struct Refinement: Sendable {
    let time: TimeInterval
    let confidence: Double
  }

  struct Word: Sendable {
    let token: String
    let time: TimeInterval
  }

  enum RefinerError: Error {
    case exportFailed
    case fileTooLarge(Int64)
  }

  /// Remote tracks larger than this are not downloaded for refinement.
  private static let maximumDownloadSize: Int64 = 400 * 1024 * 1024
  /// The legacy recognizer rejects requests longer than about a minute when it runs on a server.
  private static let legacyChunkLength: TimeInterval = 50
  private static let analyzerChunkLength: TimeInterval = 180
  private static let minimumSupport = 4.0
  private static let minimumConfidence = 0.2

  static func requestAuthorization() async -> Bool {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    case .notDetermined:
      break
    @unknown default:
      break
    }

    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  struct Located: Sendable {
    let refinement: Refinement
    let candidate: AudioPositionEstimator.Estimate
  }

  /// Longest stretch of audio transcribed in one go.
  private static let maximumSegmentLength: TimeInterval = 300

  /// Checks the candidates in order, sharing one growing transcript between them and stopping
  /// as soon as the page is found. Audio already transcribed for an earlier candidate is not
  /// transcribed again.
  static func locate(
    candidates: [AudioPositionEstimator.Estimate],
    sources: [AudioSource],
    pageTokens: [String],
    locale: Locale,
    onProgress: @escaping @Sendable (String) -> Void
  ) async throws -> Located? {
    guard pageTokens.count >= 3, !sources.isEmpty, !candidates.isEmpty else { return nil }

    let engine = try await Engine.make(locale: locale)
    var transcript: [Word] = []
    var covered: [ClosedRange<TimeInterval>] = []

    for (position, candidate) in candidates.enumerated() {
      try Task.checkCancellation()
      onProgress(progressMessage(for: candidate, position: position, total: candidates.count))

      let window = max(0, candidate.time - candidate.searchRadius)...(candidate.time + candidate.searchRadius)
      for range in subtract(window, covered) {
        var segmentStart = range.lowerBound
        while segmentStart < range.upperBound {
          try Task.checkCancellation()

          let segmentEnd = min(segmentStart + maximumSegmentLength, range.upperBound)
          guard let source = sources.first(where: { $0.startOffset <= segmentStart && segmentStart < $0.endOffset })
          else { break }

          let localStart = segmentStart - source.startOffset
          let localEnd = min(segmentEnd, source.endOffset) - source.startOffset
          guard localEnd - localStart > 1 else {
            segmentStart = source.endOffset
            continue
          }

          let fileURL = try await exportSegment(of: source, from: localStart, to: localEnd)
          defer { try? FileManager.default.removeItem(at: fileURL) }

          let started = Date()
          let words = try await engine.transcribe(fileURL)
          AppLogger.viewModel.info(
            "Page Sync: transcribed \(Int(segmentStart))s-\(Int(segmentEnd))s in \(Int(Date().timeIntervalSince(started)))s: \(words.count) words, starts \"\(words.prefix(8).map(\.token).joined(separator: " "))\""
          )
          transcript += words.map { Word(token: $0.token, time: segmentStart + $0.time) }
          transcript.sort { $0.time < $1.time }
          covered.append(segmentStart...segmentEnd)

          if let refinement = align(pageTokens: pageTokens, transcript: transcript) {
            return Located(refinement: refinement, candidate: candidate)
          }

          segmentStart = source.startOffset + localEnd
        }
      }
    }

    return nil
  }

  /// Plain transcript of a stretch of audio, with absolute times.
  static func transcribe(
    range: ClosedRange<TimeInterval>,
    sources: [AudioSource],
    locale: Locale
  ) async throws -> [Word] {
    let engine = try await Engine.make(locale: locale)
    var transcript: [Word] = []
    var segmentStart = max(0, range.lowerBound)

    while segmentStart < range.upperBound {
      try Task.checkCancellation()
      let segmentEnd = min(segmentStart + maximumSegmentLength, range.upperBound)
      guard let source = sources.first(where: { $0.startOffset <= segmentStart && segmentStart < $0.endOffset })
      else { break }

      let localStart = segmentStart - source.startOffset
      let localEnd = min(segmentEnd, source.endOffset) - source.startOffset
      guard localEnd - localStart > 1 else {
        segmentStart = source.endOffset
        continue
      }

      let fileURL = try await exportSegment(of: source, from: localStart, to: localEnd)
      defer { try? FileManager.default.removeItem(at: fileURL) }

      let words = try await engine.transcribe(fileURL)
      AppLogger.viewModel.info("Page Sync: transcribed \(Int(segmentStart))s-\(Int(segmentEnd))s: \(words.count) words")
      transcript += words.map { Word(token: $0.token, time: segmentStart + $0.time) }
      segmentStart = source.startOffset + localEnd
    }

    return transcript.sorted { $0.time < $1.time }
  }

  private static func progressMessage(
    for candidate: AudioPositionEstimator.Estimate,
    position: Int,
    total: Int
  ) -> String {
    if position == 0 {
      return String(localized: "Listening to the audio…")
    }
    if let title = candidate.chapterTitle {
      return String(localized: "Not there yet. Checking \(title)…")
    }
    return String(localized: "Not there yet. Checking another spot (\(position + 1) of \(total))…")
  }

  /// Parts of `range` not already covered by `covered`.
  private static func subtract(
    _ range: ClosedRange<TimeInterval>,
    _ covered: [ClosedRange<TimeInterval>]
  ) -> [ClosedRange<TimeInterval>] {
    var remaining = [range]
    for block in covered {
      remaining = remaining.flatMap { piece -> [ClosedRange<TimeInterval>] in
        guard piece.overlaps(block) else { return [piece] }
        var result: [ClosedRange<TimeInterval>] = []
        if piece.lowerBound < block.lowerBound {
          result.append(piece.lowerBound...block.lowerBound)
        }
        if block.upperBound < piece.upperBound {
          result.append(block.upperBound...piece.upperBound)
        }
        return result
      }
    }
    return remaining.filter { $0.upperBound - $0.lowerBound > 5 }
  }

  /// Finds where the beginning of the page is spoken in the transcript.
  ///
  /// Every word pair shared by the page and the transcript votes for the transcript index at
  /// which the page would start; the index with the most votes wins. Pairs made only of short
  /// or very common words count less, since they match by chance all over the book.
  static func align(pageTokens: [String], transcript: [Word]) -> Refinement? {
    let head = Array(pageTokens.prefix(100))
    guard head.count >= 2, transcript.count >= 2 else { return nil }

    var pageBigrams: [String: [Int]] = [:]
    for index in 0..<(head.count - 1) {
      pageBigrams[head[index] + " " + head[index + 1], default: []].append(index)
    }

    var votes: [Int: Double] = [:]
    for index in 0..<(transcript.count - 1) {
      let first = transcript[index].token
      let second = transcript[index + 1].token
      guard let positions = pageBigrams[first + " " + second] else { continue }
      let weight = isDistinctive(first) || isDistinctive(second) ? 1.0 : 0.35
      for position in positions {
        votes[index - position, default: 0] += weight
      }
    }

    guard let winner = votes.max(by: { $0.value < $1.value })?.key else {
      AppLogger.viewModel.info(
        "Page Sync: no shared word pairs between page (\(head.count) words) and transcript (\(transcript.count) words)"
      )
      return nil
    }

    let support = (winner - 2...winner + 2).reduce(0.0) { $0 + (votes[$1] ?? 0) }
    let confidence = min(1, support / Double(min(head.count - 1, 30)))
    AppLogger.viewModel.info(
      "Page Sync: best alignment at transcript word \(winner) with \(String(format: "%.1f", support)) votes, confidence \(String(format: "%.2f", confidence))"
    )
    guard support >= minimumSupport, confidence >= minimumConfidence else { return nil }

    let index = min(max(0, winner), transcript.count - 1)
    return Refinement(time: transcript[index].time, confidence: confidence)
  }

  private static let stopwords: Set<String> = [
    "the", "and", "a", "an", "of", "to", "in", "on", "at", "for", "with", "was", "were", "is", "are", "be",
    "he", "she", "it", "they", "his", "her", "its", "their", "had", "has", "have", "not", "but", "that",
    "this", "as", "by", "from", "or", "so", "if", "then", "than", "you", "i", "we", "me", "him", "them",
    "my", "your", "our", "s", "t", "d", "ll", "el", "la", "los", "las", "de", "del", "que", "y", "en", "un",
    "una", "es", "se", "no", "por", "con", "su", "sus", "al", "lo", "le", "como", "para", "pero",
  ]

  private static func isDistinctive(_ token: String) -> Bool {
    token.count >= 4 && !stopwords.contains(token)
  }

  // MARK: - Audio

  /// AVAssetExportSession cannot trim remote assets, so remote tracks are downloaded once to a
  /// temporary file and trimmed from there.
  private static func localFile(for source: AudioSource) async throws -> URL {
    if source.url.isFileURL {
      return source.url
    }

    let cached = RemoteTrackCache.shared.url(for: source.url)
    if let cached, FileManager.default.fileExists(atPath: cached.path) {
      return cached
    }

    var request = URLRequest(url: source.url)
    for (field, value) in source.headers {
      request.setValue(value, forHTTPHeaderField: field)
    }

    var headRequest = request
    headRequest.httpMethod = "HEAD"
    if let (_, response) = try? await URLSession.shared.data(for: headRequest),
      let length = (response as? HTTPURLResponse)?.expectedContentLength, length > maximumDownloadSize
    {
      throw RefinerError.fileTooLarge(length)
    }

    let started = Date()
    let (downloadedURL, response) = try await URLSession.shared.download(for: request)
    if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
      try? FileManager.default.removeItem(at: downloadedURL)
      throw RefinerError.exportFailed
    }

    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("page-sync-track-\(UUID().uuidString)")
      .appendingPathExtension(source.url.pathExtension.isEmpty ? "audio" : source.url.pathExtension)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: downloadedURL, to: destination)
    RemoteTrackCache.shared.store(destination, for: source.url)

    let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
    AppLogger.viewModel.info(
      "Page Sync: downloaded track (\(size / 1_048_576) MB) in \(Int(Date().timeIntervalSince(started)))s"
    )
    return destination
  }

  private static func exportSegment(
    of source: AudioSource,
    from start: TimeInterval,
    to end: TimeInterval
  ) async throws -> URL {
    let fileURL = try await localFile(for: source)
    let asset = AVURLAsset(url: fileURL)
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      throw RefinerError.exportFailed
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("page-sync-\(UUID().uuidString)")
      .appendingPathExtension("m4a")

    session.timeRange = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      end: CMTime(seconds: end, preferredTimescale: 600)
    )

    if #available(iOS 18.0, *) {
      try await session.export(to: outputURL, as: .m4a)
    } else {
      session.outputURL = outputURL
      session.outputFileType = .m4a
      await session.export()
      guard session.status == .completed else {
        throw session.error ?? RefinerError.exportFailed
      }
    }

    return outputURL
  }

  // MARK: - Speech engines

  /// The iOS 26 `SpeechAnalyzer` handles long files and reports word timings; older systems fall
  /// back to `SFSpeechRecognizer`, collecting every partial final until the task ends.
  private enum Engine {
    case analyzer(locale: Locale)
    case legacy(SFSpeechRecognizer)

    var isAnalyzer: Bool {
      if case .analyzer = self { return true }
      return false
    }

    static func make(locale: Locale) async throws -> Engine {
      if #available(iOS 26.0, *), SpeechTranscriber.isAvailable,
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
      {
        let transcriber = SpeechTranscriber(
          locale: supported,
          transcriptionOptions: [],
          reportingOptions: [],
          attributeOptions: [.audioTimeRange]
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        AppLogger.viewModel.info(
          "Page Sync: SpeechAnalyzer \(supported.identifier), assets \(String(describing: status))"
        )
        if status != .installed,
          let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        {
          AppLogger.viewModel.info("Page Sync: downloading speech model for \(supported.identifier)")
          try await request.downloadAndInstall()
        }
        return .analyzer(locale: supported)
      }

      guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
        recognizer.isAvailable
      else {
        AppLogger.viewModel.warning("Page Sync: no speech recognizer for \(locale.identifier)")
        throw RefinerError.exportFailed
      }
      AppLogger.viewModel.info(
        "Page Sync: SFSpeechRecognizer \(recognizer.locale.identifier), on-device \(recognizer.supportsOnDeviceRecognition)"
      )
      return .legacy(recognizer)
    }

    func transcribe(_ url: URL) async throws -> [Word] {
      switch self {
      case .analyzer(let locale):
        if #available(iOS 26.0, *) {
          return try await SpeechAlignmentRefiner.transcribeWithAnalyzer(url, locale: locale)
        }
        return []
      case .legacy(let recognizer):
        return try await SpeechAlignmentRefiner.transcribeWithLegacyRecognizer(url, recognizer: recognizer)
      }
    }
  }

  @available(iOS 26.0, *)
  private static func transcribeWithAnalyzer(_ url: URL, locale: Locale) async throws -> [Word] {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let audioFile = try AVAudioFile(forReading: url)

    async let collected = collectWords(from: transcriber)
    _ = try await analyzer.analyzeSequence(from: audioFile)
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    return try await collected
  }

  @available(iOS 26.0, *)
  private static func collectWords(from transcriber: SpeechTranscriber) async throws -> [Word] {
    var words: [Word] = []
    for try await result in transcriber.results {
      let text = result.text
      for run in text.runs {
        guard let timeRange = run.audioTimeRange else { continue }
        let fragment = String(text[run.range].characters)
        for token in PageTextNormalizer.tokens(fragment) {
          words.append(Word(token: token, time: timeRange.start.seconds))
        }
      }
    }
    return words
  }

  private static func transcribeWithLegacyRecognizer(_ url: URL, recognizer: SFSpeechRecognizer) async throws -> [Word]
  {
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    let collector = LegacyCollector()
    return try await withCheckedThrowingContinuation { continuation in
      collector.continuation = continuation
      collector.task = recognizer.recognitionTask(with: request, delegate: collector)
    }
  }

  /// Gathers every final result the legacy recognizer produces (it finalizes at long pauses)
  /// and resumes once the task is over.
  private final class LegacyCollector: NSObject, SFSpeechRecognitionTaskDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<[Word], Error>?
    var task: SFSpeechRecognitionTask?
    private var words: [Word] = []
    private let lock = NSLock()

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult)
    {
      lock.lock()
      defer { lock.unlock() }
      for segment in result.bestTranscription.segments {
        for token in PageTextNormalizer.tokens(segment.substring) {
          words.append(Word(token: token, time: segment.timestamp))
        }
      }
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
      lock.lock()
      defer { lock.unlock() }
      guard let continuation else { return }
      self.continuation = nil
      if successfully {
        continuation.resume(returning: words)
      } else if let error = task.error as NSError?, error.domain != "kAFAssistantErrorDomain" {
        continuation.resume(throwing: error)
      } else {
        // Silence or music in the window is reported as an error; treat it as an empty transcript.
        continuation.resume(returning: words)
      }
    }
  }

  /// Remote tracks downloaded during this app session, so several candidates in the same
  /// track share one download.
  private final class RemoteTrackCache: @unchecked Sendable {
    static let shared = RemoteTrackCache()

    private let lock = NSLock()
    private var files: [URL: URL] = [:]

    func url(for remote: URL) -> URL? {
      lock.lock()
      defer { lock.unlock() }
      return files[remote]
    }

    func store(_ local: URL, for remote: URL) {
      lock.lock()
      defer { lock.unlock() }
      files[remote] = local
    }
  }
}
