import SwiftUI

struct BookPlayerControls: View {
  @ObservedObject var model: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    HStack(spacing: 0) {
      if let chapters = model.chapters, chapters.chapters.count > 1, !preferences.hideChapterSkipButtons {
        Button(action: {
          Haptics.impact(.light)
          chapters.onPreviousChapterTapped()
        }) {
          Image(systemName: "backward.end")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor((model.isLoading || !chapters.canGoPreviousChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(!chapters.canGoPreviousChapter)
        .accessibilityLabel("Previous chapter")
      }

      Spacer(minLength: 8)

      Button(action: {
        Haptics.impact(.light)
        model.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
      }) {
        Image(
          systemName: "gobackward.\(Int(preferences.skipBackwardInterval))"
        )
        .font(
          .system(
            size: preferences.hideChapterSkipButtons ? 32 : 28,
            weight: .regular
          )
        )
        .minimumScaleFactor(0.5)
        .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")

      Spacer(minLength: 8)

      Button(action: {
        Haptics.impact(.medium)
        model.onTogglePlaybackTapped()
      }) {
        ZStack {
          if model.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 48))
              .foregroundColor(.white)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .frame(maxWidth: 80, maxHeight: 80)
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

      Spacer(minLength: 8)

      Button(action: {
        Haptics.impact(.light)
        model.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
      }) {
        Image(systemName: "goforward.\(Int(preferences.skipForwardInterval))")
          .font(
            .system(
              size: preferences.hideChapterSkipButtons ? 32 : 28,
              weight: .regular
            )
          )
          .minimumScaleFactor(0.5)
          .foregroundColor(model.isLoading ? .white.opacity(0.3) : .white)
      }
      .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")

      Spacer(minLength: 8)

      if let chapters = model.chapters, chapters.chapters.count > 1, !preferences.hideChapterSkipButtons {
        Button(action: {
          Haptics.impact(.light)
          chapters.onNextChapterTapped()
        }) {
          Image(systemName: "forward.end")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor((model.isLoading || !chapters.canGoNextChapter) ? .white.opacity(0.3) : .white)
        }
        .disabled(!chapters.canGoNextChapter)
        .accessibilityLabel("Next chapter")
      }
    }
    .buttonStyle(.borderless)
    .opacity(model.isLocked ? 0.4 : 1)
    .padding(.horizontal)
  }
}
