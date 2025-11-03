import AppIntents
import Foundation

struct SetSleepTimerToEndOfChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Set sleep timer to end of chapter"
  static let description = IntentDescription(
    "Sets the sleep timer to pause at the end of a specified number of chapters.")
  static let openAppWhenRun = false

  @Parameter(
    title: "Chapters",
    description: "Number of chapters (0 = current chapter)",
    default: 0
  )
  var chapters: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Set sleep timer to end of \(\.$chapters) chapters")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard currentPlayer.chapters != nil else {
        throw AppIntentError.noChapters
      }

      let timer = currentPlayer.timer
      let chapterCount = max(1, chapters + 1)

      guard chapterCount <= timer.maxRemainingChapters else {
        throw AppIntentError.notEnoughChapters(max: timer.maxRemainingChapters)
      }

      timer.onChaptersChanged(chapterCount)
      timer.onStartTimerTapped()

      return chapterCount == 1
        ? "Sleep timer set to end of current chapter"
        : "Sleep timer set to end of \(chapterCount) chapters"
    }

    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}
