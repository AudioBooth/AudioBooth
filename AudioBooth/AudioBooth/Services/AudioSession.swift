import AVFAudio
import Foundation
import Logging

nonisolated enum AudioSession {
  private static let queue = DispatchQueue(label: "me.jgrenier.AudioBS.AudioSession", qos: .userInitiated)

  @MainActor
  @discardableResult
  static func configure() -> Bool {
    let otherAudioPlaying = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    let mixWithOthers = UserPreferences.shared.mixWithOtherAudio && otherAudioPlaying

    queue.async {
      do {
        let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
        let policy: AVAudioSession.RouteSharingPolicy = mixWithOthers ? .default : .longFormAudio
        try AVAudioSession.sharedInstance().setCategory(
          .playback,
          mode: .spokenAudio,
          policy: policy,
          options: options
        )
      } catch {
        AppLogger.player.error("Failed to configure audio session: \(error)")
      }
    }

    return mixWithOthers
  }

  static func activate() async {
    await withCheckedContinuation { continuation in
      queue.async {
        do {
          try AVAudioSession.sharedInstance().setActive(true)
        } catch {
          AppLogger.player.error("Failed to activate audio session: \(error)")
        }
        continuation.resume()
      }
    }
  }

  static func deactivate() {
    queue.async {
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }
}
