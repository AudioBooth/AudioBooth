import Foundation

nonisolated struct AudioChapter: Sendable {
  let title: String
  let start: TimeInterval
  let end: TimeInterval

  var duration: TimeInterval { max(0, end - start) }

  func contains(_ time: TimeInterval) -> Bool {
    start <= time && time < end
  }
}
