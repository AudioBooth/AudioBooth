import SwiftUI

struct LockScreenPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        NowPlayingPreviewCard(
          usesChapters: preferences.lockScreenNextPreviousUsesChapters,
          allowsScrubbing: preferences.lockScreenAllowPlaybackPositionChange,
          showsChapterTitle: !preferences.showFullBookDuration,
          showsRemainingInTitle: preferences.lockScreenShowRemainingInTitle,
          skipBackwardSeconds: Int(preferences.skipBackwardInterval),
          skipForwardSeconds: Int(preferences.skipForwardInterval)
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text("Skip By")
            .font(.subheadline)
            .fontWeight(.medium)
          SkipBySegmented(usesChapters: $preferences.lockScreenNextPreviousUsesChapters)
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.lockScreenShowRemainingInTitle) {
          PreferenceRow(
            systemImage: "clock",
            tint: .blue,
            title: "Show Remaining In Title",
            subtitle: "Append time remaining to the lock screen title"
          )
        }
        .listRowBackground(theme.colors.background.card)

        if #available(iOS 26.0, *) {
          Toggle(isOn: $preferences.lockScreenImmersiveCover) {
            PreferenceRow(
              systemImage: "rectangle.portrait.fill",
              tint: .indigo,
              title: "Immersive Cover",
              subtitle: "Show the cover full screen on the Lock Screen player"
            )
          }
          .listRowBackground(theme.colors.background.card)
        }
      } header: {
        Text("Appearance")
      }

      Section {
        Toggle(isOn: $preferences.lockScreenAllowPlaybackPositionChange) {
          PreferenceRow(
            systemImage: "slider.horizontal.below.rectangle",
            tint: .orange,
            title: "Allow Seeking",
            subtitle: "Drag the progress bar to jump to a position"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Behavior")
      } footer: {
        Text("Chapter title and cover art are controlled from Playback Display.")
          .font(.caption)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page.ignoresSafeArea())
    .navigationTitle("Lock Screen")
  }
}

private struct SkipBySegmented: View {
  @Binding var usesChapters: Bool

  var body: some View {
    HStack(spacing: 8) {
      segment(title: "Seconds", isSelected: !usesChapters) { usesChapters = false }
      segment(title: "Chapters", isSelected: usesChapters) { usesChapters = true }
    }
  }

  private func segment(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.12))
        )
    }
    .buttonStyle(.plain)
  }
}

private struct NowPlayingPreviewCard: View {
  let usesChapters: Bool
  let allowsScrubbing: Bool
  let showsChapterTitle: Bool
  let showsRemainingInTitle: Bool
  let skipBackwardSeconds: Int
  let skipForwardSeconds: Int

  private var titleText: String {
    let base = showsChapterTitle ? "Chapter 14" : "Foundation"
    return showsRemainingInTitle ? "\(base) (4h 36m remaining)" : base
  }

  private var subtitleText: String {
    showsChapterTitle ? "Foundation · Isaac Asimov" : "Isaac Asimov"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("NOW PLAYING")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.white.opacity(0.6))

      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.accentColor)
          .frame(width: 56, height: 56)

        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: titleText)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .lineLimit(1)

          Text(verbatim: subtitleText)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
        Spacer()
      }

      progressBar

      HStack {
        skipImage(forward: false)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(.white)
        Spacer()
        Image(systemName: "pause.fill")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: 56, height: 56)
          .background(Circle().fill(.white))
        Spacer()
        skipImage(forward: true)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(.white)
      }
      .padding(.horizontal, 8)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.black.opacity(0.85))
    )
  }

  @ViewBuilder
  private var progressBar: some View {
    Capsule()
      .fill(.white.opacity(0.2))
      .frame(height: 3)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(.white)
          .frame(width: 90, height: 3)
      }
      .overlay(alignment: .leading) {
        if allowsScrubbing {
          Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .offset(x: 86)
        }
      }
  }

  private func skipImage(forward: Bool) -> Image {
    if usesChapters {
      return Image(systemName: forward ? "forward.end.fill" : "backward.end.fill")
    }
    let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
    let suffix = [10, 15, 30, 45, 60, 75, 90].contains(seconds) ? "\(seconds)" : "30"
    return Image(systemName: forward ? "goforward.\(suffix)" : "gobackward.\(suffix)")
  }
}

#Preview {
  NavigationStack {
    LockScreenPreferencesView()
  }
}
