import AppIntents
import Foundation

struct SkipToPreviousChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip to previous chapter"
  static let description = IntentDescription(
    "Skips to the previous chapter in the currently playing audiobook."
  )
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard let chapters = player.chapters, let chapter = chapters.current else {
        throw AppIntentError.noChapters
      }

      let isPastChapterStart = player.current - chapter.start >= 2
      guard isPastChapterStart || chapters.currentIndex > 0 else {
        throw AppIntentError.alreadyOnFirstChapter
      }

      player.seekToChapter(at: isPastChapterStart ? chapters.currentIndex : chapters.currentIndex - 1)
    }

    return .result()
  }
}
