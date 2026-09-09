import Foundation

@available(iOS 26.0, *)
nonisolated enum NarrationExcerpt {
  private static let readCeiling: TimeInterval = 90

  static func words(
    from start: TimeInterval,
    seconds: TimeInterval,
    source: NarrationSource,
    locale: Locale
  ) async throws -> [TranscribedWord] {
    let transcriber = NarrationTranscriber(locale: locale, source: source, priority: .userInitiated)
    return try await words(from: start, seconds: seconds, using: transcriber)
  }

  static func words(
    from start: TimeInterval,
    seconds: TimeInterval,
    using transcriber: NarrationTranscriber
  ) async throws -> [TranscribedWord] {
    let ceiling = max(readCeiling, seconds)

    let collected = Collected()

    return try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await collect(from: start, seconds: seconds, using: transcriber, into: collected)
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(ceiling))
      }

      try await group.next()
      group.cancelAll()

      return await collected.words
    }
  }

  private static func collect(
    from start: TimeInterval,
    seconds: TimeInterval,
    using transcriber: NarrationTranscriber,
    into collected: Collected
  ) async throws {
    let deadline = start + seconds
    let stream = await MainActor.run { transcriber.words(from: start) { .infinity } }

    for try await word in stream {
      try Task.checkCancellation()
      if word.start > deadline { break }
      await collected.append(word)
    }
  }
}

private actor Collected {
  private(set) var words: [TranscribedWord] = []

  func append(_ word: TranscribedWord) {
    words.append(word)
  }
}
