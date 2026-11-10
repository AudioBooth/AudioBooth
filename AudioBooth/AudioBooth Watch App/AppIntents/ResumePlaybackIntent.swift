import AppIntents
import Foundation

struct ResumePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume last played"
  static let description = IntentDescription("Resumes the last played audiobook or podcast episode.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult {
    try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel else {
        throw AppIntentError.noAudiobookPlaying
      }

      if !player.isPlaying {
        player.togglePlayback()
      }
    }

    return .result()
  }
}
