import AppIntents
import Foundation

struct PausePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Pause playback"
  static let description = IntentDescription("Pauses the currently playing audiobook.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      if player.isPlaying {
        player.togglePlayback()
      }
    }

    return .result()
  }
}
