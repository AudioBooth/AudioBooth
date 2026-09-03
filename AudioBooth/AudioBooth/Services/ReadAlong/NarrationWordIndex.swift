import Foundation

nonisolated struct NarrationWordIndex: Sendable {
  struct Entry: Sendable {
    let normalized: String
    let sentence: Int
    let startOffsetInSentence: Int
    let endOffsetInSentence: Int
  }

  let entries: [Entry]

  private let positionsByTrigram: [Trigram: [Int32]]
  private let lowInformationWords: Set<String>

  private static let trigramLength = 3
  private static let maximumTrigramOccurrences = 24
  private static let defaultCandidateLimit = 12
  private static let lowInformationFrequencyDivisor = 200
  private static let minimumLowInformationOccurrences = 5

  var count: Int { entries.count }
  var isEmpty: Bool { entries.isEmpty }

  subscript(position: Int) -> Entry { entries[position] }

  init(entries: [Entry]) {
    self.entries = entries

    let words = entries.map(\.normalized)
    positionsByTrigram = Self.indexTrigrams(in: words)
    lowInformationWords = Self.mostRepeatedWords(in: words)
  }

  func isLowInformation(_ word: String) -> Bool {
    lowInformationWords.contains(word)
  }

  private static func mostRepeatedWords(in words: [String]) -> Set<String> {
    var occurrences: [String: Int] = [:]
    for word in words {
      occurrences[word, default: 0] += 1
    }

    let threshold = max(
      minimumLowInformationOccurrences,
      words.count / lowInformationFrequencyDivisor
    )

    return Set(occurrences.filter { $0.value >= threshold }.keys)
  }

  func candidateStarts(for query: [String], limit: Int = defaultCandidateLimit) -> [Int] {
    var votesByStart: [Int32: Int] = [:]

    for (offset, trigram) in Self.trigrams(in: query) {
      for position in positionsByTrigram[trigram] ?? [] {
        let start = position - Int32(offset)
        guard start >= 0 else { continue }
        votesByStart[start, default: 0] += 1
      }
    }

    return
      votesByStart
      .sorted(by: mostVotesThenEarliestPosition)
      .prefix(limit)
      .map { Int($0.key) }
  }

  private func mostVotesThenEarliestPosition(
    _ lhs: (key: Int32, value: Int),
    _ rhs: (key: Int32, value: Int)
  ) -> Bool {
    lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
  }

  private static func indexTrigrams(in words: [String]) -> [Trigram: [Int32]] {
    var positions: [Trigram: [Int32]] = [:]
    positions.reserveCapacity(words.count)

    for (offset, trigram) in trigrams(in: words) {
      positions[trigram, default: []].append(Int32(offset))
    }

    for (trigram, occurrences) in positions where occurrences.count > maximumTrigramOccurrences {
      positions.removeValue(forKey: trigram)
    }

    return positions
  }

  private static func trigrams(in words: [String]) -> [(offset: Int, trigram: Trigram)] {
    guard words.count >= trigramLength else { return [] }

    return (0...words.count - trigramLength).map { offset in
      (offset, Trigram(words[offset], words[offset + 1], words[offset + 2]))
    }
  }
}

nonisolated private struct Trigram: Hashable {
  private let hash: Int

  init(_ first: String, _ second: String, _ third: String) {
    var hasher = Hasher()
    hasher.combine(first)
    hasher.combine(second)
    hasher.combine(third)
    hash = hasher.finalize()
  }
}
