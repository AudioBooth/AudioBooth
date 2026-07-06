import SwiftUI

/// Menu « Lecture » exposé dans la barre de menus du build Mac (Catalyst).
///
/// Réplique les actions déjà câblées par `MPRemoteCommandCenter`
/// (`PlayerManager.setupRemoteCommandCenter()`) en déléguant à
/// `PlayerManager.shared.current`, sans dupliquer de logique de lecture.
struct PlaybackCommands: Commands {
  @ObservedObject private var playerManager = PlayerManager.shared

  private var current: BookPlayer.Model? {
    playerManager.current
  }

  private var hasChapters: Bool {
    !(current?.chapters?.chapters.isEmpty ?? true)
  }

  var body: some Commands {
    CommandMenu("Lecture") {
      Button(playerManager.isPlaying ? "Pause" : "Lecture") {
        current?.onTogglePlaybackTapped()
      }
      .keyboardShortcut("p", modifiers: .command)
      .disabled(current == nil)

      Divider()

      Button("Avancer") {
        current?.onSkipForwardTapped(seconds: UserPreferences.shared.skipForwardInterval)
      }
      .keyboardShortcut(.rightArrow, modifiers: .command)
      .disabled(current == nil)

      Button("Reculer") {
        current?.onSkipBackwardTapped(seconds: UserPreferences.shared.skipBackwardInterval)
      }
      .keyboardShortcut(.leftArrow, modifiers: .command)
      .disabled(current == nil)

      Divider()

      Button("Chapitre suivant") {
        current?.chapters?.onNextChapterTapped()
      }
      .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
      .disabled(!hasChapters)

      Button("Chapitre précédent") {
        current?.chapters?.onPreviousChapterTapped()
      }
      .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
      .disabled(!hasChapters)

      Divider()

      Button("Accélérer") {
        current?.speed.onIncrease()
      }
      .keyboardShortcut("]", modifiers: .command)
      .disabled(current == nil)

      Button("Ralentir") {
        current?.speed.onDecrease()
      }
      .keyboardShortcut("[", modifiers: .command)
      .disabled(current == nil)

      Divider()

      Button("Augmenter le volume") {
        current?.volume.onIncrease()
      }
      .keyboardShortcut(.upArrow, modifiers: .command)
      .disabled(current == nil)

      Button("Baisser le volume") {
        current?.volume.onDecrease()
      }
      .keyboardShortcut(.downArrow, modifiers: .command)
      .disabled(current == nil)
    }
  }
}
