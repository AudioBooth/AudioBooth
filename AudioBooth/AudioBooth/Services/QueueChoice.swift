import Foundation

struct QueueChoice {
  enum Action {
    case play
    case addToQueue
  }

  enum Scope {
    case unfinished
    case all
  }

  let action: Action
  let unfinishedCount: Int
  let totalCount: Int
}
