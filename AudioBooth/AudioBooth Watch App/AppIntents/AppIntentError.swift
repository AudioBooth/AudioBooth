import Foundation

enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
  case noAudiobookPlaying
  case noChapters
  case alreadyOnFirstChapter
  case alreadyOnLastChapter
  case notEnoughChapters(max: Int)
  case invalidDuration
  case bookmarkAlreadyExists

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .noAudiobookPlaying:
      return "No audiobook is currently playing."
    case .noChapters:
      return "The current audiobook does not have chapters."
    case .alreadyOnFirstChapter:
      return "Already on the first chapter."
    case .alreadyOnLastChapter:
      return "Already on the last chapter."
    case .notEnoughChapters(let max):
      return "Not enough remaining chapters. Maximum is \(max)."
    case .invalidDuration:
      return "Duration must be greater than 0 minutes."
    case .bookmarkAlreadyExists:
      return "A bookmark already exists at this position."
    }
  }
}
