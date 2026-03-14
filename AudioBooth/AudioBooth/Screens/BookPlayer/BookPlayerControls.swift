import SwiftUI

struct BookPlayerControls: View {
  @ObservedObject var model: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    HStack(spacing: 0) {
      if let chapters = model.chapters, !preferences.hideChapterSkipButtons {
        Button(action: { chapters.onPreviousChapterTapped() }) {
          Image(systemName: "backward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || !chapters.canGoPreviousChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(!chapters.canGoPreviousChapter)
        .accessibilityLabel("Previous chapter")
      }

      Spacer(minLength: 8)

      Button(action: { model.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval) }) {
        Image(
          systemName: "\(Int(preferences.skipBackwardInterval)).arrow.trianglehead.counterclockwise"
        )
        .font(
          .system(
            size: preferences.hideChapterSkipButtons ? 40 : 36,
            weight: .thin
          )
        )
        .minimumScaleFactor(0.5)
        .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")

      Spacer(minLength: 8)

      Button(action: model.onTogglePlaybackTapped) {
        ZStack {
          Circle()
            .fill(model.isLoading ? Color.white.opacity(0.3) : Color.white)

          if model.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .black))
              .scaleEffect(0.8)
          } else {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 32))
              .foregroundColor(.black)
              .offset(x: model.isPlaying ? 0 : 3)
              .padding()
          }
        }
      }
      .frame(maxWidth: 80, maxHeight: 80)
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

      Spacer(minLength: 8)

      Button(action: { model.onSkipForwardTapped(seconds: preferences.skipForwardInterval) }) {
        Image(systemName: "\(Int(preferences.skipForwardInterval)).arrow.trianglehead.clockwise")
          .font(
            .system(
              size: preferences.hideChapterSkipButtons ? 40 : 36,
              weight: .thin
            )
          )
          .minimumScaleFactor(0.5)
          .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .fontWeight(.light)
      .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")

      Spacer(minLength: 8)

      if let chapters = model.chapters, !preferences.hideChapterSkipButtons {
        Button(action: { chapters.onNextChapterTapped() }) {
          Image(systemName: "forward.end")
            .font(.system(size: 30, weight: .thin))
            .foregroundColor((model.isLoading || !chapters.canGoNextChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(!chapters.canGoNextChapter)
        .accessibilityLabel("Next chapter")
      }
    }
    .buttonStyle(.borderless)
  }
}
