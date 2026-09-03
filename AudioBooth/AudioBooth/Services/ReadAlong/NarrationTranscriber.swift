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

    var errorDescription: String? {
      switch self {
      case .noAudioTrack, .unsupportedAudioFormat:
        String(localized: "This audiobook's audio can't be analyzed for Read Along.")
      case .readFailed:
        String(localized: "Couldn't read the audiobook's audio.")
      }
    }
  }

  private let locale: Locale
  private let source: NarrationSource

  private static let maximumSecondsAheadOfPlayhead: TimeInterval = 90
  private static let secondsBetweenPlayheadChecks: TimeInterval = 2
  private static let secondsBetweenFinalizations: TimeInterval = 15
  private static let playheadRecheckDelay = Duration.seconds(2)
  private static let timescale: CMTimeScale = 600

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

  func words(
    from bookTime: TimeInterval,
    playhead: @Sendable @escaping () async -> TimeInterval?
  ) -> AsyncThrowingStream<TranscribedWord, any Error> {
    AsyncThrowingStream { continuation in
      let reading = Task.detached(priority: .utility) {
        do {
          try await self.transcribe(from: bookTime, playhead: playhead) { continuation.yield($0) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in reading.cancel() }
    }
  }
}

@available(iOS 26.0, *)
nonisolated private extension NarrationTranscriber {
  func transcribe(
    from bookTime: TimeInterval,
    playhead: @Sendable @escaping () async -> TimeInterval?,
    yield: @Sendable @escaping (TranscribedWord) -> Void
  ) async throws {
    guard let start = source.locate(bookTime: bookTime) else { return }

    let transcriber = ReadAlongAvailability.makeTranscriber(locale: locale)
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw Failure.unsupportedAudioFormat
    }

    let (audio, audioContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    let publishing = Task {
      for try await result in transcriber.results {
        let words = result.timedWords
        for word in words {
          yield(word)
        }
      }
    }

    do {
      try await analyzer.start(inputSequence: audio)
      try await feedTracks(
        from: start,
        into: audioContinuation,
        analyzerFormat: analyzerFormat,
        playhead: playhead,
        analyzer: analyzer,
        inputTimeline: InputTimeline(sampleRate: analyzerFormat.sampleRate)
      )
      audioContinuation.finish()
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      try await publishing.value
    } catch {
      audioContinuation.finish()
      publishing.cancel()
      await analyzer.cancelAndFinishNow()
      throw error
    }
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
    var buffersFed = 0

    while let sampleBuffer = reader.output.copyNextSampleBuffer() {
      try Task.checkCancellation()

      let bookTime = track.secondsFromStartOfBook + sampleBuffer.presentationTimeStamp.seconds

      if bookTime >= nextPlayheadCheck {
        try await waitUntilPlayheadIsNear(bookTime, playhead: playhead)
        nextPlayheadCheck = bookTime + Self.secondsBetweenPlayheadChecks
      }

      guard let buffer = sampleBuffer.pcmBuffer(format: reader.readerFormat) else { continue }
      let input = try reader.converter.map { try buffer.converted(using: $0, to: analyzerFormat) } ?? buffer
      guard let startTime = inputTimeline.startTime(at: bookTime, frames: input.frameLength) else { continue }

      continuation.yield(AnalyzerInput(buffer: input, bufferStartTime: startTime))
      buffersFed += 1

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
  ) async throws {
    while true {
      try Task.checkCancellation()

      if let current = await playhead(), current + Self.maximumSecondsAheadOfPlayhead >= bookTime {
        return
      }

      try await Task.sleep(for: Self.playheadRecheckDelay)
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
