import AppIntents
import Foundation

struct SetSleepTimerWithDurationIntent: AppIntent {
  static let title: LocalizedStringResource = "Set sleep timer with duration"
  static let description = IntentDescription(
    "Sets the sleep timer to pause after a specified duration.")
  static let openAppWhenRun = false

  @Parameter(
    title: "Duration",
    description: "Duration for the sleep timer",
    defaultValue: 15,
    defaultUnit: .minutes,
    supportsNegativeNumbers: false
  )
  var duration: Measurement<UnitDuration>

  static var parameterSummary: some ParameterSummary {
    Summary("Set sleep timer for \(\.$duration)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let totalSeconds = Int(duration.converted(to: .seconds).value)

    guard totalSeconds > 0 else {
      throw AppIntentError.invalidDuration
    }

    let message = try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      let timer = currentPlayer.timer

      let minutes = Int(ceil(Double(totalSeconds) / 60.0))
      timer.onQuickTimerSelected(minutes)

      let hours = totalSeconds / 3600
      let mins = (totalSeconds % 3600) / 60

      if hours > 0 && mins > 0 {
        return
          "Sleep timer set to \(hours) hour\(hours > 1 ? "s" : "") and \(mins) minute\(mins > 1 ? "s" : "")"
      } else if hours > 0 {
        return "Sleep timer set to \(hours) hour\(hours > 1 ? "s" : "")"
      } else if mins > 0 {
        return "Sleep timer set to \(mins) minute\(mins > 1 ? "s" : "")"
      } else {
        return "Sleep timer set to \(totalSeconds) second\(totalSeconds > 1 ? "s" : "")"
      }
    }

    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}
