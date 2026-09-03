import Foundation

nonisolated struct TranscriptAligner {
  struct AlignedWord: Sendable, Equatable {
    let queryIndex: Int
    let bookWord: Int
  }

  struct Alignment: Sendable {
    let words: [AlignedWord]
    let score: Double

    var firstBookWord: Int? { words.first?.bookWord }
    var lastBookWord: Int? { words.last?.bookWord }

    func expectedStartOfNextWindow(stride: Int) -> Int? {
      words.first { $0.queryIndex >= stride }?.bookWord ?? lastBookWord
    }
  }

  fileprivate enum Move {
    case matchWords
    case skipQueryWord
    case skipBookWord
  }

  let words: NarrationWordIndex

  var minimumScore: Double = 0.55

  private let minimumQueryLength = 3
  private let windowPaddingWords = 12
  private let maximumContinuityBonus = 0.12
  private let continuityRangeInWords = 200
  private let skipPenalty = -1.0
  private let mismatchPenalty = -1.0
  private let lowInformationWeight = 0.35
  private let contentWordWeight = 1.0

  func align(query: [String], expectedStart: Int?) -> Alignment? {
    guard query.count >= minimumQueryLength, !words.isEmpty else { return nil }

    let queryWeight = query.reduce(0.0) { $0 + informationWeight(of: $1) }
    guard queryWeight > 0 else { return nil }

    let best = candidateStarts(for: query, expectedStart: expectedStart)
      .compactMap { start in fit(query: query, in: window(around: start, for: query), queryWeight: queryWeight) }
      .max { rank($0, expectedStart: expectedStart) < rank($1, expectedStart: expectedStart) }

    guard let best, best.score >= minimumScore else { return nil }
    return best
  }

  private func candidateStarts(for query: [String], expectedStart: Int?) -> [Int] {
    var starts = words.candidateStarts(for: query)
    if let expectedStart, !starts.contains(expectedStart) {
      starts.append(expectedStart)
    }
    return starts
  }

  private func window(around start: Int, for query: [String]) -> Range<Int> {
    let lower = max(0, start - windowPaddingWords)
    let upper = min(words.count, start + query.count + windowPaddingWords)
    return lower..<max(lower, upper)
  }

  private func rank(_ alignment: Alignment, expectedStart: Int?) -> Double {
    alignment.score + continuityBonus(for: alignment, expectedStart: expectedStart)
  }

  private func continuityBonus(for alignment: Alignment, expectedStart: Int?) -> Double {
    guard let expectedStart, let first = alignment.firstBookWord else { return 0 }

    let distance = Double(abs(first - expectedStart))
    let range = Double(continuityRangeInWords)
    guard distance <= range else { return 0 }

    return maximumContinuityBonus * (1 - distance / range)
  }

  private func informationWeight(of word: String) -> Double {
    words.isLowInformation(word) ? lowInformationWeight : contentWordWeight
  }
}

nonisolated private extension TranscriptAligner {
  private func fit(query: [String], in window: Range<Int>, queryWeight: Double) -> Alignment? {
    guard window.count >= minimumQueryLength else { return nil }

    var table = AlignmentTable(rows: query.count, columns: window.count, skipPenalty: skipPenalty)

    for row in 1...table.rows {
      let queryWord = query[row - 1]
      let matchReward = informationWeight(of: queryWord)

      for column in 1...table.columns {
        let bookWord = words[window.lowerBound + column - 1].normalized
        table.fill(
          row: row,
          column: column,
          matchScore: queryWord == bookWord ? matchReward : mismatchPenalty,
          skipPenalty: skipPenalty
        )
      }
    }

    let matched = table.path
      .filter { query[$0.row - 1] == words[window.lowerBound + $0.column - 1].normalized }
      .map { AlignedWord(queryIndex: $0.row - 1, bookWord: window.lowerBound + $0.column - 1) }

    guard !matched.isEmpty else { return nil }

    let matchedWeight = matched.reduce(0.0) { $0 + informationWeight(of: query[$1.queryIndex]) }
    return Alignment(words: matched, score: matchedWeight / queryWeight)
  }
}

nonisolated private struct AlignmentTable {
  let rows: Int
  let columns: Int

  private var scores: [Double]
  private var moves: [TranscriptAligner.Move]

  init(rows: Int, columns: Int, skipPenalty: Double) {
    self.rows = rows
    self.columns = columns
    scores = [Double](repeating: 0, count: (rows + 1) * (columns + 1))
    moves = [TranscriptAligner.Move](repeating: .matchWords, count: (rows + 1) * (columns + 1))

    for row in 1...rows {
      scores[index(row, 0)] = scores[index(row - 1, 0)] + skipPenalty
      moves[index(row, 0)] = .skipQueryWord
    }
  }

  mutating func fill(row: Int, column: Int, matchScore: Double, skipPenalty: Double) {
    var bestScore = scores[index(row - 1, column - 1)] + matchScore
    var bestMove = TranscriptAligner.Move.matchWords

    let skippingQueryWord = scores[index(row - 1, column)] + skipPenalty
    if skippingQueryWord > bestScore {
      bestScore = skippingQueryWord
      bestMove = .skipQueryWord
    }

    let skippingBookWord = scores[index(row, column - 1)] + skipPenalty
    if skippingBookWord > bestScore {
      bestScore = skippingBookWord
      bestMove = .skipBookWord
    }

    scores[index(row, column)] = bestScore
    moves[index(row, column)] = bestMove
  }

  var path: [(row: Int, column: Int)] {
    var row = rows
    var column = bestEndColumn
    var steps: [(row: Int, column: Int)] = []

    while row > 0, column > 0 {
      switch moves[index(row, column)] {
      case .matchWords:
        steps.append((row, column))
        row -= 1
        column -= 1
      case .skipQueryWord:
        row -= 1
      case .skipBookWord:
        column -= 1
      }
    }

    return steps.reversed()
  }

  private var bestEndColumn: Int {
    (0...columns).max { scores[index(rows, $0)] < scores[index(rows, $1)] } ?? 0
  }

  private func index(_ row: Int, _ column: Int) -> Int {
    row * (columns + 1) + column
  }
}
