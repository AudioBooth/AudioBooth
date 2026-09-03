import Foundation
import Logging
import ReadiumShared

@MainActor
@Observable
final class ReadAlongCoordinator {
  enum Status: Equatable {
    case off
    case preparing(Double)
    case locating
    case following
    case failed(String)

    var isActive: Bool {
      switch self {
      case .off, .failed: false
      case .preparing, .locating, .following: true
      }
    }
  }

  private(set) var status: Status = .off {
    didSet {
      guard status.isActive != oldValue.isActive else { return }
      onActiveChanged?()
    }
  }

  private(set) var sentenceLocator: Locator?
  private(set) var wordLocator: Locator?

  var onActiveChanged: (() -> Void)?
  var onFollow: ((_ sentence: Locator, _ word: Locator?) -> Void)?
  var onHighlightChanged: ((_ sentence: Locator?, _ word: Locator?) -> Void)?

  var highlightsWord: Bool = true {
    didSet {
      guard !highlightsWord, wordLocator != nil else { return }
      wordLocator = nil
      onHighlightChanged?(sentenceLocator, nil)
    }
  }

  var followsNarration: Bool = true

  private let publication: Publication
  private let source: NarrationSource
  private let playhead: @MainActor () -> TimeInterval?

  private var index: BookTextIndex?
  private var aligner: TranscriptAligner?
  private var locale: Locale?

  private var prepareTask: Task<Void, Never>?
  private var indexTask: Task<BookTextIndex, Never>?
  private var transcriptionTask: Task<Void, Never>?
  private var highlightTask: Task<Void, Never>?

  private var pendingWords: [TranscribedWord] = []
  private var timeline = NarrationTimeline()
  private var narratorPosition: Int?
  private var highlightedSentence: Int?
  private var highlightedWord: Int?
  private var previousPlayhead: TimeInterval?
  private var previousPlayheadAt: Date?
  private var isAwaitingNavigation = false
  private var lastMatchAt: Date?
  private var isWaitingForPlayheadToSettle = false
  private var playheadStableSince: Date?
  private var timelineCoveredPlayheadAt: Date?
  private var lastRecoveryAt: Date?

  private static let alignmentWindowSize = 16
  private static let alignmentWindowStride = 8
  private static let minimumWordsToAlign = 6
  private static let secondsIndicatingSeek: TimeInterval = 3
  private static let fastestPlaybackRate: Double = 4
  private static let secondsOfStablePlayheadBeforeResuming: TimeInterval = 1.5
  private static let secondsBeforeConsideredLost: TimeInterval = 45
  private static let secondsOfSilenceBeforeRecovering: TimeInterval = 20
  private static let secondsBetweenRecoveries: TimeInterval = 30
  private static let secondsOfRunUpBeforePlayhead: TimeInterval = 2
  private static let highlightRefreshInterval = Duration.milliseconds(100)
  private static let modelDownloadShareOfPreparation = 0.5

  init(
    publication: Publication,
    source: NarrationSource,
    playhead: @escaping @MainActor () -> TimeInterval?
  ) {
    self.publication = publication
    self.source = source
    self.playhead = playhead
  }

  func start() {
    guard !status.isActive else { return }

    guard #available(iOS 26.0, *) else {
      status = .failed(String(localized: "Read Along requires iOS 26 or later."))
      return
    }

    guard !source.tracks.isEmpty else {
      status = .failed(String(localized: "This book has no audio to follow."))
      return
    }

    status = .preparing(0)
    prepareTask = Task { [weak self] in
      await self?.prepare()
    }
  }

  func stop() {
    prepareTask?.cancel()
    indexTask?.cancel()
    transcriptionTask?.cancel()
    highlightTask?.cancel()
    prepareTask = nil
    indexTask = nil
    transcriptionTask = nil
    highlightTask = nil

    pendingWords.removeAll()
    timeline.removeAll()
    narratorPosition = nil
    highlightedSentence = nil
    highlightedWord = nil
    previousPlayhead = nil
    previousPlayheadAt = nil
    isAwaitingNavigation = false
    lastMatchAt = nil
    isWaitingForPlayheadToSettle = false
    playheadStableSince = nil
    timelineCoveredPlayheadAt = nil
    lastRecoveryAt = nil
    sentenceLocator = nil
    wordLocator = nil
    status = .off
    onHighlightChanged?(nil, nil)
  }

  func narrationDidLand() {
    isAwaitingNavigation = false
    markNarrationVisible()
  }

  func markNarrationVisible() {
    guard status == .locating else { return }
    status = .following
  }

  func toggle() {
    switch status {
    case .off:
      start()
    case .failed:
      stop()
      start()
    case .preparing, .locating, .following:
      stop()
    }
  }
}

@available(iOS 26.0, *)
private extension ReadAlongCoordinator {
  func prepare() async {
    guard !isPrepared else {
      beginListening()
      return
    }

    guard let resolved = await resolveLocale() else { return }
    guard await verifyAudioIsReadable(using: resolved) else { return }
    guard let built = await buildIndex() else { return }

    index = built
    aligner = TranscriptAligner(words: built.words)
    locale = resolved

    AppLogger.readAlong.info(
      "Ready: \(built.words.count) words, \(built.sentences.count) sentences, locale \(resolved.identifier)"
    )

    beginListening()
  }

  func resolveLocale() async -> Locale? {
    let preferred =
      publication.metadata.language
      .map { Locale(identifier: $0.code.bcp47) } ?? Locale.current

    do {
      let resolved = try await ReadAlongAvailability.prepare(preferred: preferred) { [weak self] fraction in
        guard let self else { return }
        Task { await self.reportModelDownload(fraction) }
      }
      return Task.isCancelled ? nil : resolved
    } catch is CancellationError {
      return nil
    } catch {
      guard !Task.isCancelled else { return nil }
      status = .failed(error.localizedDescription)
      return nil
    }
  }

  func verifyAudioIsReadable(using locale: Locale) async -> Bool {
    do {
      try await NarrationTranscriber(locale: locale, source: source).verifyAudioIsReadable()
      return true
    } catch is CancellationError {
      return false
    } catch {
      guard !Task.isCancelled else { return false }
      status = .failed(error.localizedDescription)
      return false
    }
  }

  func buildIndex() async -> BookTextIndex? {
    status = .preparing(Self.modelDownloadShareOfPreparation)

    let build = Task.detached(priority: .userInitiated) { [publication] in
      await BookTextIndex.build(publication: publication) { fraction in
        Task { @MainActor [weak self] in
          let remaining = 1 - Self.modelDownloadShareOfPreparation
          self?.status = .preparing(Self.modelDownloadShareOfPreparation + fraction * remaining)
        }
      }
    }

    indexTask = build
    let built = await build.value
    indexTask = nil

    guard !Task.isCancelled, !build.isCancelled else { return nil }
    guard !built.isEmpty else {
      status = .failed(String(localized: "Couldn't read any text from this ebook."))
      return nil
    }

    return built
  }

  var currentBookTime: TimeInterval? { playhead() }

  var isPrepared: Bool { index != nil && locale != nil }

  func reportModelDownload(_ fraction: Double) {
    status = .preparing(fraction * Self.modelDownloadShareOfPreparation)
  }

  func beginListening() {
    status = .locating
    lastMatchAt = Date()
    timelineCoveredPlayheadAt = Date()
    startTranscription(from: playhead() ?? 0)
    startHighlighting()
  }

  func startTranscription(from bookTime: TimeInterval) {
    guard let locale else { return }

    let supersededRun = transcriptionTask
    supersededRun?.cancel()

    let start = max(0, bookTime - Self.secondsOfRunUpBeforePlayhead)
    pendingWords.removeAll()
    timeline.removeFrom(start)

    let transcriber = NarrationTranscriber(locale: locale, source: source)
    let trackCount = source.tracks.count

    transcriptionTask = Task { [weak self] in
      await supersededRun?.value

      guard self != nil, !Task.isCancelled else { return }
      AppLogger.readAlong.info("Transcribing from \(start)s across \(trackCount) track(s)")

      let words = transcriber.words(from: start) { [weak self] in
        await self?.currentBookTime
      }

      defer { AppLogger.readAlong.info("Stopped transcribing from \(start)s") }

      do {
        for try await word in words {
          guard let self, !Task.isCancelled else { return }
          self.collect(word)
        }
        guard let self, !Task.isCancelled else { return }
        self.flushPendingWords()
      } catch {
        guard let self, !Task.isCancelled else { return }
        AppLogger.readAlong.error("Transcription failed: \(error)")
        self.status = .failed(error.localizedDescription)
      }
    }
  }

  func flushPendingWords() {
    guard pendingWords.count >= Self.minimumWordsToAlign else { return }
    locate(pendingWords)
    pendingWords.removeAll()
  }

  func collect(_ word: TranscribedWord) {
    pendingWords.append(word)

    while pendingWords.count >= Self.alignmentWindowSize {
      locate(Array(pendingWords.prefix(Self.alignmentWindowSize)))
      pendingWords.removeFirst(Self.alignmentWindowStride)
    }
  }

  func locate(_ narratedWords: [TranscribedWord]) {
    guard let aligner else { return }

    let query = narratedWords.map(\.normalized)

    guard let alignment = aligner.align(query: query, expectedStart: narratorPosition) else {
      noteUnmatchedNarration()
      return
    }

    lastMatchAt = Date()
    narratorPosition = alignment.expectedStartOfNextWindow(stride: Self.alignmentWindowStride)

    for aligned in alignment.words {
      timeline.append(bookWord: aligned.bookWord, at: narratedWords[aligned.queryIndex].start)
    }

  }

  func noteUnmatchedNarration() {
    guard status == .following, let lastMatchAt,
      Date().timeIntervalSince(lastMatchAt) > Self.secondsBeforeConsideredLost
    else {
      return
    }

    status = .locating
    clearHighlight()
  }

  func startHighlighting() {
    highlightTask?.cancel()
    highlightTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.highlightRefreshInterval)
        guard let self, !Task.isCancelled else { return }
        self.refreshHighlight()
      }
    }
  }

  func refreshHighlight() {
    guard let bookTime = playhead() else {
      stopBecausePlaybackEnded()
      return
    }
    let now = Date()
    defer {
      previousPlayhead = bookTime
      previousPlayheadAt = now
    }

    if let previousPlayhead, let previousPlayheadAt,
      abs(bookTime - previousPlayhead) > plausibleAdvance(since: previousPlayheadAt, now: now)
    {
      beginWaitingForPlayheadToSettle()
      return
    }

    if isWaitingForPlayheadToSettle {
      let stableSince = playheadStableSince ?? Date()
      playheadStableSince = stableSince

      guard
        Date().timeIntervalSince(stableSince) >= Self.secondsOfStablePlayheadBeforeResuming
      else {
        return
      }

      isWaitingForPlayheadToSettle = false
      playheadStableSince = nil
      handleSeek(to: bookTime)
      return
    }

    guard let index else { return }

    guard let bookWord = timeline.bookWord(at: bookTime) else {
      if highlightedWord != nil {
        highlightedWord = nil
        clearHighlight()
      }
      recoverIfNarrationWentSilent(at: bookTime, advancedFrom: previousPlayhead)
      return
    }

    timelineCoveredPlayheadAt = now

    guard bookWord != highlightedWord else { return }

    highlightedWord = bookWord
    moveSentenceHighlight(to: bookWord, in: index)
    wordLocator = highlightsWord ? index.wordLocator(forWord: bookWord) : nil
    onHighlightChanged?(sentenceLocator, wordLocator)
    follow(bookWord, in: index)

    if !isAwaitingNavigation {
      markNarrationVisible()
    }
  }

  func plausibleAdvance(since: Date, now: Date) -> TimeInterval {
    now.timeIntervalSince(since) * Self.fastestPlaybackRate + Self.secondsIndicatingSeek
  }

  func moveSentenceHighlight(to bookWord: Int, in index: BookTextIndex) {
    guard let sentence = index.words.entries[safe: bookWord]?.sentence,
      sentence != highlightedSentence,
      let locator = index.sentenceLocator(forWord: bookWord)
    else {
      return
    }

    highlightedSentence = sentence
    sentenceLocator = locator
  }

  func follow(_ bookWord: Int, in index: BookTextIndex) {
    guard followsNarration, let sentence = sentenceLocator else { return }

    isAwaitingNavigation = true
    onFollow?(sentence, index.wordLocator(forWord: bookWord))
  }

  func recoverIfNarrationWentSilent(at bookTime: TimeInterval, advancedFrom previous: TimeInterval?) {
    guard let previous, bookTime > previous, source.covers(bookTime: bookTime) else { return }

    let silentSince = timelineCoveredPlayheadAt ?? lastMatchAt ?? Date()
    let now = Date()

    guard now.timeIntervalSince(silentSince) > Self.secondsOfSilenceBeforeRecovering,
      now.timeIntervalSince(lastRecoveryAt ?? .distantPast) > Self.secondsBetweenRecoveries
    else {
      return
    }

    AppLogger.readAlong.info("No narration reached \(bookTime)s, listening again from there")
    lastRecoveryAt = now
    relocate(from: bookTime)
  }

  func beginWaitingForPlayheadToSettle() {
    playheadStableSince = nil
    guard !isWaitingForPlayheadToSettle else { return }
    isWaitingForPlayheadToSettle = true
    timelineCoveredPlayheadAt = Date()
    highlightedWord = nil
    clearHighlight()
  }

  func handleSeek(to bookTime: TimeInterval) {
    highlightedWord = nil
    highlightedSentence = nil

    guard !timeline.covers(bookTime) else {
      narratorPosition = timeline.bookWord(at: bookTime)
      return
    }

    relocate(from: bookTime)
  }

  func relocate(from bookTime: TimeInterval) {
    narratorPosition = nil
    clearHighlight()
    lastMatchAt = Date()
    timelineCoveredPlayheadAt = Date()
    status = .locating
    startTranscription(from: bookTime)
  }

  func stopBecausePlaybackEnded() {
    AppLogger.viewModel.info("Read Along stopped: the audiobook it was following is no longer loaded")
    stop()
  }

  func clearHighlight() {
    highlightedWord = nil
    highlightedSentence = nil
    sentenceLocator = nil
    wordLocator = nil
    onHighlightChanged?(nil, nil)
  }
}

nonisolated private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
