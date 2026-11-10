import AppIntents
import Foundation

struct CancelSleepTimerIntent: AppIntent {
  static let title: LocalizedStringResource = "Cancel sleep timer"
  static let description = IntentDescription("Cancels any active sleep timer.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      player.options.timer.onCancelTapped()
    }

    return .result(dialog: "Sleep timer cancelled")
  }
}
