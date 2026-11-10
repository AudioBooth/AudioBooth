import AppIntents
import Foundation

struct SkipToNextChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip to next chapter"
  static let description = IntentDescription(
    "Skips to the next chapter in the currently playing audiobook."
  )
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard let chapters = player.chapters else {
        throw AppIntentError.noChapters
      }

      guard chapters.currentIndex < chapters.chapters.count - 1 else {
        throw AppIntentError.alreadyOnLastChapter
      }

      player.seekToChapter(at: chapters.currentIndex + 1)
    }

    return .result()
  }
}
