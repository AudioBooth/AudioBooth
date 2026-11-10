import AppIntents
import Foundation

struct SetSleepTimerWithDurationIntent: AppIntent {
  static let title: LocalizedStringResource = "Set sleep timer with duration"
  static let description = IntentDescription(
    "Sets the sleep timer to pause after a specified duration."
  )
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
    let minutes = Int(ceil(duration.converted(to: .minutes).value))

    guard minutes > 0 else {
      throw AppIntentError.invalidDuration
    }

    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      player.options.timer.onMinutesSelected(minutes)
    }

    let formatted = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    return .result(dialog: "Sleep timer set to \(formatted)")
  }
}
