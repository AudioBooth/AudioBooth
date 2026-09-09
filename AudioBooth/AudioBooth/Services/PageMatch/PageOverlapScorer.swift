import Foundation

nonisolated struct PageOverlapScorer: Sendable {
  private let pageWords: Set<String>
  private let isLowInformation: @Sendable (String) -> Bool

  static let lowInformationWeight = 0.2
  static let contentWordWeight = 1.0
  private static let shortWordLength = 3

  init(pageWords: [String], isLowInformation: @escaping @Sendable (String) -> Bool) {
    self.pageWords = Set(pageWords)
    self.isLowInformation = isLowInformation
  }

  init(pageWords: [String]) {
    self.init(pageWords: pageWords, isLowInformation: { _ in false })
  }

  var isUsable: Bool { !pageWords.isEmpty }

  func score(against transcript: some Sequence<String>) -> Double {
    var matched = 0.0
    var total = 0.0
    var counted: Set<String> = []

    for word in transcript where counted.insert(word).inserted {
      let weight = self.weight(for: word)
      total += weight
      if pageWords.contains(word) {
        matched += weight
      }
    }

    guard total > 0 else { return 0 }
    return matched / total
  }

  private func weight(for word: String) -> Double {
    let isCommon = word.count <= Self.shortWordLength || isLowInformation(word)
    return isCommon ? Self.lowInformationWeight : Self.contentWordWeight
  }
}
