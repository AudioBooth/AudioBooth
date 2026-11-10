import AppIntents
import Foundation

struct SetSleepTimerToEndOfChapterIntent: AppIntent {
  static let title: LocalizedStringResource = "Set sleep timer to end of chapter"
  static let description = IntentDescription(
    "Sets the sleep timer to pause at the end of a specified number of chapters."
  )
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
    let chapterCount = try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      let timer = player.options.timer
      timer.onAppear()

      guard timer.hasChapters else {
        throw AppIntentError.noChapters
      }

      let chapterCount = max(1, chapters + 1)
      guard chapterCount <= timer.maxChapters else {
        throw AppIntentError.notEnoughChapters(max: timer.maxChapters)
      }

      timer.onChaptersSelected(chapterCount)
      return chapterCount
    }

    if chapterCount == 1 {
      return .result(dialog: "Sleep timer set to end of current chapter")
    }
    return .result(dialog: "Sleep timer set to end of \(chapterCount) chapters")
  }
}
