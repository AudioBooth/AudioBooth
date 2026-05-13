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
      } header: {
        Text("Skip Buttons")
      } footer: {
        Text("Choose what the lock screen previous and next buttons do.")
          .font(.caption)
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
    .background(theme.colors.background.page)
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
  let skipBackwardSeconds: Int
  let skipForwardSeconds: Int

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
          Text(verbatim: showsChapterTitle ? "Chapter 14" : "The Wandering Earth")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)

          Text(verbatim: showsChapterTitle ? "The Wandering Earth · Liu Cixin" : "Liu Cixin")
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
