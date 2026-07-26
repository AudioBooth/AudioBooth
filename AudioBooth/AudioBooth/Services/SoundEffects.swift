import AVFoundation
import Foundation

/// Plays short UI sound effects. Because these players share the app's already
/// active `.playback` audio session, they mix over any ongoing audiobook
/// playback without pausing or ducking it.
enum SoundEffects {
  private static var player: AVAudioPlayer?

  /// A subtle chime confirming a bookmark was saved. Non-interrupting: the book
  /// keeps playing underneath it.
  static func playBookmark() {
    play(resource: "bookmark_tone", extension: "wav", volume: 0.6)
  }

  private static func play(resource: String, extension ext: String, volume: Float) {
    guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
      AppLogger.player.debug("Sound effect \(resource).\(ext) not found in bundle")
      return
    }

    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.volume = volume
      player.prepareToPlay()
      player.play()
      // Retain so it isn't deallocated before it finishes playing.
      self.player = player
    } catch {
      AppLogger.player.debug("Failed to play sound effect \(resource): \(error)")
    }
  }
}
