import AppIntents
import Foundation

struct SkipToPreviousChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip to previous chapter"
  static let description = IntentDescription(
    "Skips to the previous chapter in the currently playing audiobook.")
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

      let isFirstChapter = chapters.currentIndex == 0
      guard !isFirstChapter else {
        throw AppIntentError.alreadyOnFirstChapter
      }

      chapters.onPreviousChapterTapped()
    }

    return .result()
  }
}
