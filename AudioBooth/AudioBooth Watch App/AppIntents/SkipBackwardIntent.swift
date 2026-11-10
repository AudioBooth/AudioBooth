import AppIntents
import Foundation

struct SkipBackwardIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip backward the given time"
  static let description = IntentDescription(
    "Skips backward in the currently playing audiobook by a specified duration."
  )
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
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      player.skip(by: -duration.converted(to: .seconds).value)
    }

    return .result()
  }
}
