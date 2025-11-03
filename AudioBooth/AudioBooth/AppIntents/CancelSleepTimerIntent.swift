import AppIntents
import Foundation

struct CancelSleepTimerIntent: AppIntent {
  static let title: LocalizedStringResource = "Cancel sleep timer"
  static let description = IntentDescription("Cancels any active sleep timer.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      let timer = currentPlayer.timer

      if case .none = currentPlayer.timer.current {
        throw AppIntentError.noActiveTimer
      }

      timer.onOffSelected()
    }

    return .result(dialog: "Sleep timer cancelled")
  }
}
