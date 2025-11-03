import AppIntents
import Foundation

struct ResumePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Resume last played audiobook"
  static let description = IntentDescription("Resumes the last played audiobook.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard !currentPlayer.isPlaying else {
        throw AppIntentError.playbackAlreadyActive
      }

      currentPlayer.onTogglePlaybackTapped()
    }

    return .result()
  }
}
