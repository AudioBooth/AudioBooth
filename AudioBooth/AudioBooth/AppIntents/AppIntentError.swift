import Foundation

enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
  case noAudiobookPlaying
  case playbackAlreadyPaused
  case playbackAlreadyActive
  case noChapters
  case alreadyOnFirstChapter
  case alreadyOnLastChapter
  case timerNotAvailable
  case notEnoughChapters(max: Int)
  case invalidDuration
  case noActiveTimer
  case custom(String)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .noAudiobookPlaying:
      return "No audiobook is currently playing."
    case .playbackAlreadyPaused:
      return "Playback is already paused."
    case .playbackAlreadyActive:
      return "Playback is already active."
    case .noChapters:
      return "The current audiobook does not have chapters."
    case .alreadyOnFirstChapter:
      return "Already on the first chapter."
    case .alreadyOnLastChapter:
      return "Already on the last chapter."
    case .timerNotAvailable:
      return "Timer is not available."
    case .notEnoughChapters(let max):
      return "Not enough remaining chapters. Maximum is \(max)."
    case .invalidDuration:
      return "Duration must be greater than 0 minutes."
    case .noActiveTimer:
      return "No active sleep timer to cancel."
    case .custom(let message):
      return LocalizedStringResource(stringLiteral: message)
    }
  }
}
