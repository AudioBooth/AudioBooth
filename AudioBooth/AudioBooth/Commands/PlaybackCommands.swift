import Combine
import SwiftUI

struct PlaybackCommands: Commands {
  @ObservedObject private var playerManager = PlayerManager.shared

  var body: some Commands {
    CommandMenu("Playback") {
      Button(playerManager.isPlaying ? "Pause" : "Play") {
        playerManager.current?.onTogglePlaybackTapped()
      }
      .keyboardShortcut("p", modifiers: .command)
      .disabled(playerManager.current == nil)

      Divider()

      Button("Skip Forward") {
        playerManager.current?.onSkipForwardTapped(seconds: UserPreferences.shared.skipForwardInterval)
      }
      .keyboardShortcut(.rightArrow, modifiers: .command)
      .disabled(playerManager.current == nil)

      Button("Skip Back") {
        playerManager.current?.onSkipBackwardTapped(seconds: UserPreferences.shared.skipBackwardInterval)
      }
      .keyboardShortcut(.leftArrow, modifiers: .command)
      .disabled(playerManager.current == nil)

      Divider()

      Button("Next Chapter") {
        playerManager.current?.chapters?.onNextChapterTapped()
      }
      .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
      .disabled(playerManager.current?.chapters?.chapters.isEmpty != false)

      Button("Previous Chapter") {
        playerManager.current?.chapters?.onPreviousChapterTapped()
      }
      .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
      .disabled(playerManager.current?.chapters?.chapters.isEmpty != false)

      Divider()

      Button("Speed Up") {
        playerManager.current?.speed.onIncrease()
      }
      .keyboardShortcut("]", modifiers: .command)
      .disabled(playerManager.current == nil)

      Button("Slow Down") {
        playerManager.current?.speed.onDecrease()
      }
      .keyboardShortcut("[", modifiers: .command)
      .disabled(playerManager.current == nil)

      Divider()

      Button("Volume Up") {
        playerManager.current?.volume.onIncrease()
      }
      .keyboardShortcut(.upArrow, modifiers: .command)
      .disabled(playerManager.current == nil)

      Button("Volume Down") {
        playerManager.current?.volume.onDecrease()
      }
      .keyboardShortcut(.downArrow, modifiers: .command)
      .disabled(playerManager.current == nil)
    }
  }
}
