import SwiftUI

struct PlayerPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        NarrationSpeedCard(speed: $preferences.defaultPlaybackSpeed)
          .listRowInsets(EdgeInsets())
          .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.timeRemainingAdjustsWithSpeed) {
          PreferenceRow(
            systemImage: "clock.arrow.circlepath",
            tint: .orange,
            title: "Adjusts Time Remaining",
            subtitle: "Time displays scale with speed"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.chapterProgressionAdjustsWithSpeed) {
          PreferenceRow(
            systemImage: "slider.horizontal.below.rectangle",
            tint: .pink,
            title: "Adjusts Chapter Progression",
            subtitle: "Chapter time displays scale with speed"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Narration Speed")
      }

      Section {
        Toggle(isOn: $preferences.openPlayerOnLaunch) {
          PreferenceRow(
            systemImage: "play.circle",
            tint: .green,
            title: "Open Player on Launch",
            subtitle: "Skip the home screen on reopen"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.keepScreenAwakeInPlayer) {
          PreferenceRow(
            systemImage: "sun.max",
            tint: .yellow,
            title: "Keep Screen Awake",
            subtitle: "Prevent auto-lock while the player is open"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.mixWithOtherAudio) {
          PreferenceRow(
            systemImage: "speaker.wave.2",
            tint: .blue,
            title: "Mix with Other Audio",
            subtitle: "Play alongside music from other apps"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Behavior")
      }

      Section {
        Toggle(isOn: $preferences.smartContinuePlayback) {
          PreferenceRow(
            systemImage: "wand.and.stars",
            tint: .indigo,
            title: "Smart Continue",
            subtitle: "Automatically play the next book in the series, downloaded book, or podcast episode"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Up Next")
      }

      Section {
        NavigationLink {
          ControlsLayoutPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "slider.horizontal.3",
            tint: .orange,
            title: "Controls & Layout",
            subtitle: controlsLayoutSubtitle
          )
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink {
          SkipRewindPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "gobackward",
            tint: .orange,
            title: "Skip & Smart Rewind",
            subtitle:
              "Back \(Int(preferences.skipBackwardInterval))s · Forward \(Int(preferences.skipForwardInterval))s"
          )
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink {
          SleepPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "moon",
            tint: .purple,
            title: "Sleep Timer & Alarm",
            subtitle: sleepShakeSubtitle
          )
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink {
          PlaybackDisplayPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "play.square",
            tint: .indigo,
            title: "Playback Display",
            subtitle: playbackDisplaySubtitle
          )
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink {
          LockScreenPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "lock",
            tint: .blue,
            title: "Lock Screen",
            subtitle: preferences.lockScreenNextPreviousUsesChapters ? "Skip by chapters" : "Skip by seconds"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Configure")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Player")
  }

  private var controlsLayoutSubtitle: String {
    let enabled = preferences.playerControls
    let extraCount = max(PlayerControl.allCases.count - 3, 0)
    let names = enabled.prefix(3).map { String(localized: $0.displayName) }.joined(separator: ", ")
    return extraCount > 0 ? "\(names) +\(extraCount)" : names
  }

  private var sleepShakeSubtitle: String {
    let sensitivity = preferences.shakeSensitivity.displayText
    switch preferences.autoTimerMode {
    case .off: return String(localized: "Sensitivity: \(sensitivity)")
    case .duration(let s):
      let mins = Int(s / 60)
      return String(localized: "\(mins) min · \(sensitivity)")
    case .chapters(let n):
      return String(localized: "\(n) chapter \(sensitivity)")
    }
  }

  private var playbackDisplaySubtitle: String {
    preferences.playerOrientation.displayText
  }
}

private struct NarrationSpeedCard: View {
  @Binding var speed: Double

  private var presets: [Double] {
    UserDefaults.standard.array(forKey: "speedPresets") as? [Double] ?? [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Default for new books")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(speed, format: .number.precision(.fractionLength(2)))
              .font(.system(size: 44, weight: .bold))
              .foregroundStyle(Color.accentColor)
            Text(verbatim: "×")
              .font(.title3)
              .fontWeight(.bold)
              .foregroundStyle(Color.accentColor)
          }
        }
        Spacer()
        VStack(spacing: 8) {
          stepperButton(systemImage: "plus", tint: Color.accentColor, foreground: .white) {
            speed = min(3.5, (speed + 0.05).rounded(toPlaces: 2))
          }
          stepperButton(systemImage: "minus", tint: Color.gray.opacity(0.15), foreground: .primary) {
            speed = max(0.5, (speed - 0.05).rounded(toPlaces: 2))
          }
        }
      }

      HStack(spacing: 6) {
        ForEach(presets, id: \.self) { value in
          presetChip(value)
        }
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    .padding(16)
  }

  private func presetChip(_ value: Double) -> some View {
    let isSelected = abs(speed - value) < 0.001
    return Button {
      speed = value
    } label: {
      Text(value, format: .number.precision(.fractionLength(2)))
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.black : Color.gray.opacity(0.12))
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func stepperButton(
    systemImage: String,
    tint: Color,
    foreground: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(tint)
        .frame(width: 50, height: 44)
        .overlay(
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(foreground)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private extension Double {
  func rounded(toPlaces places: Int) -> Double {
    let factor = pow(10.0, Double(places))
    return (self * factor).rounded() / factor
  }
}

#Preview {
  NavigationStack {
    PlayerPreferencesView()
  }
}
