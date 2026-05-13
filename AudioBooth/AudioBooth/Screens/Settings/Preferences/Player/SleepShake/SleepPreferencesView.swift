import SwiftUI

struct SleepPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  private let durationOptions: [TimeInterval] = [300, 600, 900, 1200, 1800, 2700, 3600]
  private let chapterOptions: [Int] = [1, 2, 3]
  private let fadeOptions: [Double] = [0, 15, 30, 60]

  private var autoSleepEnabled: Binding<Bool> {
    Binding(
      get: { preferences.autoTimerMode != .off },
      set: { isOn in
        preferences.autoTimerMode = isOn ? .duration(1800) : .off
      }
    )
  }

  private var durationSelection: Binding<AutoTimerMode> {
    Binding(
      get: {
        preferences.autoTimerMode == .off ? .duration(1800) : preferences.autoTimerMode
      },
      set: { preferences.autoTimerMode = $0 }
    )
  }

  var body: some View {
    Form {
      Section {
        Toggle(isOn: autoSleepEnabled) {
          PreferenceRow(
            systemImage: "moon",
            tint: .purple,
            title: "Auto Sleep",
            subtitle: "Start a timer when playing within a window."
          )
        }
        .listRowBackground(theme.colors.background.card)

        if preferences.autoTimerMode != .off {
          Picker(selection: durationSelection) {
            ForEach(durationOptions, id: \.self) { seconds in
              Text(durationLabel(seconds)).tag(AutoTimerMode.duration(seconds))
            }
            ForEach(chapterOptions, id: \.self) { count in
              Text(chapterLabel(count)).tag(AutoTimerMode.chapters(count))
            }
          } label: {
            Text("Default Duration")
              .font(.subheadline)
              .fontWeight(.medium)
          }
          .listRowBackground(theme.colors.background.card)

          HStack {
            Text("Time Window")
              .font(.subheadline)
              .fontWeight(.medium)
            Spacer()
            TimePicker(minutesSinceMidnight: $preferences.autoTimerWindowStart)
            Text(verbatim: "–")
              .foregroundStyle(.secondary)
            TimePicker(minutesSinceMidnight: $preferences.autoTimerWindowEnd)
          }
          .listRowBackground(theme.colors.background.card)

          Picker(selection: $preferences.timerFadeOut) {
            ForEach(fadeOptions, id: \.self) { value in
              Text(fadeLabel(value)).tag(value)
            }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text("Audio Fade Out")
                .font(.subheadline)
                .fontWeight(.medium)
              Text("Gentle fade before stopping")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .listRowBackground(theme.colors.background.card)
        }
      } header: {
        Text("Sleep Timer")
      }

      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text("Shake Sensitivity")
            .font(.subheadline)
            .fontWeight(.medium)
          ShakeSensitivityRow(selection: $preferences.shakeSensitivity)
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Shake to Reset")
      } footer: {
        Text("Shake your phone during playback to reset the timer.")
          .font(.caption)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Sleep & Shake")
  }

  private func durationLabel(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .abbreviated))
  }

  private func chapterLabel(_ count: Int) -> String {
    count == 1 ? String(localized: "End of chapter") : String(localized: "End of \(count) chapters")
  }

  private func fadeLabel(_ value: Double) -> String {
    if value == 0 { return String(localized: "Off") }
    return Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated))
  }
}

private struct ShakeSensitivityRow: View {
  @Binding var selection: ShakeSensitivity

  private let order: [ShakeSensitivity] = [.off, .low, .medium, .high]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(order, id: \.self) { level in
        Button {
          selection = level
        } label: {
          Text(level.displayText)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(selection == level ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == level ? Color.accentColor : Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct TimePicker: View {
  @Binding var minutesSinceMidnight: Int

  private var date: Binding<Date> {
    Binding(
      get: {
        let calendar = Calendar.current
        let hours = minutesSinceMidnight / 60
        let minutes = minutesSinceMidnight % 60
        return calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: Date()) ?? Date()
      },
      set: { newDate in
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: newDate)
        let minute = calendar.component(.minute, from: newDate)
        minutesSinceMidnight = hour * 60 + minute
      }
    )
  }

  var body: some View {
    DatePicker(selection: date, displayedComponents: .hourAndMinute) {}
      .labelsHidden()
  }
}

#Preview {
  NavigationStack {
    SleepPreferencesView()
  }
}
