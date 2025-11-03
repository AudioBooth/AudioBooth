import AppIntents
import Foundation

struct PausePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Pause playback"
  static let description = IntentDescription("Pauses the currently playing audiobook.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      let playerManager = PlayerManager.shared

      guard let currentPlayer = playerManager.current else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard currentPlayer.isPlaying else {
        throw AppIntentError.playbackAlreadyPaused
      }

      currentPlayer.onTogglePlaybackTapped()
    }

    return .result()
  }
}
