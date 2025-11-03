import AppIntents
import Foundation

struct SkipBackwardIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip backward the given time"
  static let description = IntentDescription(
    "Skips backward in the currently playing audiobook by a specified duration.")
  static let openAppWhenRun = false

  @Parameter(
    title: "Duration",
    description: "Duration to skip backward",
    defaultValue: 30,
    defaultUnit: .seconds,
    supportsNegativeNumbers: false
  )
  var duration: Measurement<UnitDuration>

  static var parameterSummary: some ParameterSummary {
    Summary("Skip backward \(\.$duration)")
  }

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      let seconds = duration.converted(to: .seconds).value
      currentPlayer.onSkipBackwardTapped(seconds: seconds)
    }

    return .result()
  }
}
