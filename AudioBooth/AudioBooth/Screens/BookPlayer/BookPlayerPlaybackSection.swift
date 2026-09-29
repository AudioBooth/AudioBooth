import SwiftUI

struct BookPlayerPlaybackSection: View {
  @ObservedObject var model: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(spacing: 32) {
      PlaybackProgressView(model: $model.playbackProgress)
        .tint(progressTint)
      BookPlayerControls(model: model)
    }
  }

  private var progressTint: Color? {
    guard preferences.coverColorProgressBar, let tint = model.progressTint else {
      return preferences.accentColor
    }
    return tint
  }
}
