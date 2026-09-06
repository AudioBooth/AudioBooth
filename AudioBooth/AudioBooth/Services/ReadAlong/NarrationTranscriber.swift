@preconcurrency import AVFoundation
import Foundation
import Logging
import Speech

@available(iOS 26.0, *)
nonisolated final class NarrationTranscriber: Sendable {
  enum Failure: LocalizedError {
    case noAudioTrack
    case unsupportedAudioFormat
    case readFailed(any Error)
    case analyzerStopped

    var errorDescription: String? {
      switch self {
      case .noAudioTrack, .unsupportedAudioFormat:
        String(localized: "This audiobook's audio can't be analyzed for Read Along.")
      case .readFailed:
        String(localized: "Couldn't read the audiobook's audio.")
      case .analyzerStopped:
        String(localized: "Read Along lost the narration and couldn't pick it back up.")
      }
    }
  }

  private let locale: Locale
  private let source: NarrationSource

  private static let maximumSecondsAheadOfPlayhead: TimeInterval = 300
  private static let secondsBetweenPlayheadChecks: TimeInterval = 2
  private static let secondsBetweenFinalizations: TimeInterval = 15
  private static let playheadRecheckDelay = Duration.seconds(2)
  private static let timescale: CMTimeScale = 600
  private static let secondsBeforeRetrying: TimeInterval = 2
  private static let maximumAttemptsWithoutProgress = 4
  private static let secondsOfOverlapAfterFailure: TimeInterval = 2
  private static let minimumSecondsCountingAsProgress: TimeInterval = 5

  private static func isWorthRetrying(_ error: any Error) -> Bool {
    switch error {
    case is CancellationError, Failure.noAudioTrack, Failure.unsupportedAudioFormat: false
    default: true
    }
  }

  init(locale: Locale, source: NarrationSource) {
    self.locale = locale
    self.source = source
  }

  func verifyAudioIsReadable() async throws {
    guard let track = source.tracks.first else { throw Failure.noAudioTrack }

    let asset = AVURLAsset(url: track.url)

    do {
      guard try await asset.loadTracks(withMediaType: .audio).first != nil else {
        throw Failure.noAudioTrack
      }
    } catch let failure as Failure {
      throw failure
    } catch {
      throw readFailure(for: track, underlying: error)
    }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw readFailure(for: track, underlying: error)
    }
    reader.cancelReading()
  }

  @MainActor
  func words(
    from bookTime: TimeInterval,
    playhead: @Sendable @escaping () async -> TimeInterval?
  ) -> AsyncThrowingStream<TranscribedWord, any Error> {
    let (stream, continuation) = AsyncThrowingStream<TranscribedWord, any Error>.makeStream()

    let session = NarrationSession.begin {
      do {
        try await self.transcribe(from: bookTime, playhead: playhead) { continuation.yield($0) }
        continuation.finish()
      } catch is CancellationError {
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }

    continuation.onTermination = { _ in session.cancel() }
    return stream
  }
}

@available(iOS 26.0, *)
nonisolated private extension NarrationTranscriber {
  func transcribe(
    from bookTime: TimeInterval,
    playhead: @Sendable @escaping () async -> TimeInterval?,
    yield: @Sendable @escaping (TranscribedWord) -> Void
  ) async throws {
    var resumeAt = bookTime
    var attemptsWithoutProgress = 0

    while true {
      guard let start = source.locate(bookTime: resumeAt) else { return }

      let progress = SessionProgress()

      do {
        try await runSession(from: start, playhead: playhead) {
          progress.record($0)
          yield($0)
        }
        return
      } catch {
        try Task.checkCancellation()
        guard Self.isWorthRetrying(error) else { throw error }

        if let reached = progress.lastWordStart, reached > resumeAt + Self.minimumSecondsCountingAsProgress {
          resumeAt = reached - Self.secondsOfOverlapAfterFailure
          attemptsWithoutProgress = 0
        } else {
          attemptsWithoutProgress += 1
          guard attemptsWithoutProgress <= Self.maximumAttemptsWithoutProgress else { throw error }
        }

        AppLogger.readAlong.warning("Narration stopped (\(error)), listening again from \(Int(resumeAt))s")
        try await Task.sleep(for: .seconds(Self.secondsBeforeRetrying))
      }
    }
  }

  func runSession(
    from start: (trackIndex: Int, offsetInTrack: TimeInterval),
    playhead: @Sendable @escaping () async -> TimeInterval?,
    yield: @Sendable @escaping (TranscribedWord) -> Void
  ) async throws {
    let transcriber = ReadAlongAvailability.makeTranscriber(locale: locale)
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw Failure.unsupportedAudioFormat
    }

    try Task.checkCancellation()

    let (audio, audioContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    do {
      try await analyzer.start(inputSequence: audio)
    } catch {
      audioContinuation.finish()
      await analyzer.cancelAndFinishNow()
      throw error
    }

    try await withThrowingTaskGroup(of: SessionOutcome.self) { group in
      group.addTask {
        try await self.feedTracks(
          from: start,
          into: audioContinuation,
          analyzerFormat: analyzerFormat,
          playhead: playhead,
          analyzer: analyzer,
          inputTimeline: InputTimeline(sampleRate: analyzerFormat.sampleRate)
        )
        return .fedAllAudio
      }

      group.addTask {
        for try await result in transcriber.results {
          for word in result.timedWords {
            yield(word)
          }
        }
        return .resultsEnded
      }

      do {
        guard try await group.next() == .fedAllAudio else { throw Failure.analyzerStopped }
        audioContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
      } catch {
        group.cancelAll()
        audioContinuation.finish()
        await analyzer.cancelAndFinishNow()
        throw error
      }

      try await group.waitForAll()
    }
  }

  enum SessionOutcome {
    case fedAllAudio
    case resultsEnded
  }

  func feedTracks(
    from start: (trackIndex: Int, offsetInTrack: TimeInterval),
    into continuation: AsyncStream<AnalyzerInput>.Continuation,
    analyzerFormat: AVAudioFormat,
    playhead: @Sendable @escaping () async -> TimeInterval?,
    analyzer: SpeechAnalyzer,
    inputTimeline: InputTimeline
  ) async throws {
    for trackIndex in start.trackIndex..<source.tracks.count {
      try Task.checkCancellation()
      try await feed(
        source.tracks[trackIndex],
        from: trackIndex == start.trackIndex ? start.offsetInTrack : 0,
        into: continuation,
        analyzerFormat: analyzerFormat,
        playhead: playhead,
        analyzer: analyzer,
        inputTimeline: inputTimeline
      )
    }
  }

  func feed(
    _ track: NarrationSource.Track,
    from offset: TimeInterval,
    into continuation: AsyncStream<AnalyzerInput>.Continuation,
    analyzerFormat: AVAudioFormat,
    playhead: @Sendable @escaping () async -> TimeInterval?,
    analyzer: SpeechAnalyzer,
    inputTimeline: InputTimeline
  ) async throws {
    let asset = AVURLAsset(url: track.url)

    let reader = try await makeReader(for: asset, track: track, from: offset, format: analyzerFormat)
    defer { reader.reader.cancelReading() }

    AppLogger.readAlong.debug(
      "Reading \(track.url.lastPathComponent) from \(offset)s, book time \(track.secondsFromStartOfBook)s-\(track.secondsToEndOfBook)s"
    )

    var nextPlayheadCheck: TimeInterval = 0
    var nextFinalization = track.secondsFromStartOfBook + offset + Self.secondsBetweenFinalizations
    var isBehindPlayhead = false

    while let sampleBuffer = reader.output.copyNextSampleBuffer() {
      try Task.checkCancellation()

      let bookTime = track.secondsFromStartOfBook + sampleBuffer.presentationTimeStamp.seconds

      if bookTime >= nextPlayheadCheck {
        let lead = try await waitUntilPlayheadIsNear(bookTime, playhead: playhead)
        nextPlayheadCheck = bookTime + Self.secondsBetweenPlayheadChecks
        report(lead: lead, wasBehind: &isBehindPlayhead)
      }

      guard let buffer = sampleBuffer.pcmBuffer(format: reader.readerFormat) else { continue }
      let input = try reader.converter.map { try buffer.converted(using: $0, to: analyzerFormat) } ?? buffer
      guard let startTime = inputTimeline.startTime(at: bookTime, frames: input.frameLength) else { continue }

      continuation.yield(AnalyzerInput(buffer: input, bufferStartTime: startTime))

      if bookTime >= nextFinalization {
        try await analyzer.finalize(through: nil)
        nextFinalization = bookTime + Self.secondsBetweenFinalizations
      }
    }

    if reader.reader.status == .failed {
      throw readFailure(for: track, underlying: reader.reader.error)
    }
  }

  func waitUntilPlayheadIsNear(
    _ bookTime: TimeInterval,
    playhead: @Sendable @escaping () async -> TimeInterval?
  ) async throws -> TimeInterval {
    while true {
      try Task.checkCancellation()

      if let current = await playhead(), current + Self.maximumSecondsAheadOfPlayhead >= bookTime {
        return bookTime - current
      }

      try await Task.sleep(for: Self.playheadRecheckDelay)
    }
  }

  func report(lead: TimeInterval, wasBehind: inout Bool) {
    guard lead.isFinite else { return }

    if lead < 0, !wasBehind {
      wasBehind = true
      AppLogger.readAlong.warning("Transcription is \(Int(-lead))s behind the playhead")
    } else if lead >= 0, wasBehind {
      wasBehind = false
      AppLogger.readAlong.info("Transcription caught up, \(Int(lead))s ahead of the playhead")
    }
  }

  func makeReader(
    for asset: AVURLAsset,
    track: NarrationSource.Track,
    from offset: TimeInterval,
    format analyzerFormat: AVAudioFormat
  ) async throws -> TrackReader {
    let audioTracks: [AVAssetTrack]
    do {
      audioTracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
      throw readFailure(for: track, underlying: error)
    }
    guard let audioTrack = audioTracks.first else { throw Failure.noAudioTrack }

    guard let readerFormat = AVAudioFormat.monoFloat32(sampleRate: analyzerFormat.sampleRate) else {
      throw Failure.unsupportedAudioFormat
    }

    let converter: AVAudioConverter?
    if readerFormat == analyzerFormat {
      converter = nil
    } else {
      guard let made = AVAudioConverter(from: readerFormat, to: analyzerFormat) else {
        throw Failure.unsupportedAudioFormat
      }
      converter = made
    }

    let output = AVAssetReaderTrackOutput(
      track: audioTrack,
      outputSettings: AVAudioFormat.linearPCMSettings(sampleRate: analyzerFormat.sampleRate)
    )
    output.alwaysCopiesSampleData = false

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw readFailure(for: track, underlying: error)
    }

    let assetDuration = try await asset.load(.duration)
    let declaredEnd = CMTime(seconds: track.duration, preferredTimescale: Self.timescale)
    reader.timeRange = CMTimeRange(
      start: CMTime(seconds: offset, preferredTimescale: Self.timescale),
      end: track.duration > 0 ? min(assetDuration, declaredEnd) : assetDuration
    )

    guard reader.canAdd(output) else { throw Failure.unsupportedAudioFormat }
    reader.add(output)

    guard reader.startReading() else {
      throw readFailure(for: track, underlying: reader.error)
    }

    return TrackReader(reader: reader, output: output, readerFormat: readerFormat, converter: converter)
  }

  func readFailure(for track: NarrationSource.Track, underlying: (any Error)?) -> Failure {
    .readFailed(underlying ?? Failure.noAudioTrack)
  }

  struct TrackReader {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let readerFormat: AVAudioFormat
    let converter: AVAudioConverter?
  }
}

@available(iOS 26.0, *)
nonisolated private extension SpeechTranscriber.Result {
  var timedWords: [TranscribedWord] {
    text.runs.flatMap { run -> [TranscribedWord] in
      guard let range = run.audioTimeRange else { return [] }

      let tokens = String(text[run.range].characters)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      guard !tokens.isEmpty else { return [] }

      let secondsPerToken = max(range.duration.seconds, 0) / Double(tokens.count)

      return tokens.enumerated().compactMap { offset, token in
        let normalized = ReadAlongText.normalize(token)
        guard !normalized.isEmpty else { return nil }
        return TranscribedWord(
          text: String(token),
          normalized: normalized,
          start: range.start.seconds + secondsPerToken * Double(offset),
          end: range.start.seconds + secondsPerToken * Double(offset + 1)
        )
      }
    }
  }
}

nonisolated private extension AVAudioFormat {
  static func monoFloat32(sampleRate: Double) -> AVAudioFormat? {
    AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
  }

  static func linearPCMSettings(sampleRate: Double) -> [String: Any] {
    [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: true,
    ]
  }
}

nonisolated private extension CMSampleBuffer {
  func pcmBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frames = numSamples
    guard frames > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    else {
      return nil
    }

    buffer.frameLength = AVAudioFrameCount(frames)
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      self,
      at: 0,
      frameCount: Int32(frames),
      into: buffer.mutableAudioBufferList
    )

    return status == noErr ? buffer : nil
  }
}

@available(iOS 26.0, *)
nonisolated private extension AVAudioPCMBuffer {
  func converted(using converter: AVAudioConverter, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let ratio = format.sampleRate / self.format.sampleRate
    let capacity = AVAudioFrameCount(Double(frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw NarrationTranscriber.Failure.unsupportedAudioFormat
    }

    var isConsumed = false
    var conversionError: NSError?
    converter.convert(to: output, error: &conversionError) { _, status in
      guard !isConsumed else {
        status.pointee = .noDataNow
        return nil
      }
      isConsumed = true
      status.pointee = .haveData
      return self
    }

    if let conversionError { throw NarrationTranscriber.Failure.readFailed(conversionError) }
    return output
  }
}

nonisolated private final class SessionProgress: @unchecked Sendable {
  private(set) var lastWordStart: TimeInterval?

  func record(_ word: TranscribedWord) {
    lastWordStart = word.start
  }
}

nonisolated private final class InputTimeline {
  private let sampleRate: Double
  private var nextFrame: Int64?

  init(sampleRate: Double) {
    self.sampleRate = sampleRate
  }

  func startTime(at bookTime: TimeInterval, frames: AVAudioFrameCount) -> CMTime? {
    let requestedFrame = Int64((bookTime * sampleRate).rounded())
    guard requestedFrame >= nextFrame ?? requestedFrame else { return nil }

    nextFrame = requestedFrame + Int64(frames)
    return CMTime(value: requestedFrame, timescale: CMTimeScale(sampleRate))
  }
}
