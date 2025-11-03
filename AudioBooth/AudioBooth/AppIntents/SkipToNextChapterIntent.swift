import AppIntents
import Foundation

struct SkipToNextChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip to next chapter"
  static let description = IntentDescription(
    "Skips to the next chapter in the currently playing audiobook.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard let chapters = currentPlayer.chapters else {
        throw AppIntentError.noChapters
      }

      let isLastChapter = chapters.currentIndex >= chapters.chapters.count - 1
      guard !isLastChapter else {
        throw AppIntentError.alreadyOnLastChapter
      }

      chapters.onNextChapterTapped()
    }

    return .result()
  }
}
