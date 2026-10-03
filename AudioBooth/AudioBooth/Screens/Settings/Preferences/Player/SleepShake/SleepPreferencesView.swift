import SwiftUI

struct SleepPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  @State private var isEditingCustomDuration = false

  private let durationOptions: [TimeInterval] = [300, 600, 900, 1200, 1800, 2700, 3600]
  private let chapterOptions: [Int] = [1, 2, 3]
  private let fadeOptions: [Double] = [0, 15, 30, 60]
  private let alarmFadeOptions: [Double] = [0, 5, 10, 15, 30, 60]

  private var autoSleepEnabled: Binding<Bool> {
    Binding(
      get: { preferences.autoTimerMode != .off },
      set: { isOn in
        preferences.autoTimerMode = isOn ? .duration(1800) : .off
      }
    )
  }

  private var isCustomDuration: Bool {
    switch preferences.autoTimerMode {
    case .custom: true
    case .duration(let seconds): !durationOptions.contains(seconds)
    case .off, .chapters: false
    }
  }

  private var durationSelectionLabel: String {
    switch preferences.autoTimerMode {
    case .duration(let seconds), .custom(let seconds): durationLabel(seconds)
    case .chapters(let count): chapterLabel(count)
    case .off: durationLabel(1800)
    }
  }

  /// The custom value on show: the active duration while custom is selected,
  /// otherwise the last one the user dialed in.
  private var customTotalMinutes: Int {
    guard isCustomDuration, let seconds = preferences.autoTimerMode.seconds else {
      return max(1, preferences.autoTimerCustomMinutes)
    }
    return max(1, Int(seconds / 60))
  }

  private func setCustomDuration(totalMinutes: Int) {
    let totalMinutes = max(1, totalMinutes)
    preferences.autoTimerCustomMinutes = totalMinutes
    preferences.autoTimerMode = .custom(TimeInterval(totalMinutes * 60))
  }

  var body: some View {
    Form {
      Section {
        Toggle(isOn: autoSleepEnabled) {
          PreferenceRow(
            systemImage: "moon",
            tint: .purple,
            title: "Auto Sleep",
            subtitle: "Start a timer automatically while playing."
          )
        }
        .listRowBackground(theme.colors.background.card)

        if preferences.autoTimerMode != .off {
          Menu {
            ForEach(durationOptions, id: \.self) { seconds in
              durationMenuButton(
                title: durationLabel(seconds),
                isSelected: preferences.autoTimerMode == .duration(seconds)
              ) {
                preferences.autoTimerMode = .duration(seconds)
              }
            }
            ForEach(chapterOptions, id: \.self) { count in
              durationMenuButton(
                title: chapterLabel(count),
                isSelected: preferences.autoTimerMode == .chapters(count)
              ) {
                preferences.autoTimerMode = .chapters(count)
              }
            }

            Divider()

            durationMenuButton(
              title: String(localized: "Custom time"),
              isSelected: isCustomDuration
            ) {
              isEditingCustomDuration = true
            }
          } label: {
            HStack {
              Text("Default Duration")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
              Spacer()
              Text(durationSelectionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .listRowBackground(theme.colors.background.card)

          VStack(alignment: .leading, spacing: 12) {
            Text("Start During")
              .font(.subheadline)
              .fontWeight(.medium)
            AutoTimerTriggerRow(selection: $preferences.autoTimerTrigger)
            if preferences.autoTimerTrigger != .timeWindow {
              Text(
                "Add AudioBooth to any Focus under Settings → Focus → Focus Filters. The timer starts whenever that Focus is on."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .listRowBackground(theme.colors.background.card)

          if preferences.autoTimerTrigger != .focus {
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
          }

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

        VStack(alignment: .leading, spacing: 12) {
          Text("Playback Pause Behavior")
            .font(.subheadline)
            .fontWeight(.medium)
          TimerPauseBehaviorRow(selection: $preferences.timerPauseBehavior)
          Text(preferences.timerPauseBehavior.explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .listRowBackground(theme.colors.background.card)
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

      Section {
        Picker(selection: $preferences.alarmFadeOut) {
          ForEach(alarmFadeOptions, id: \.self) { value in
            Text(alarmFadeLabel(value)).tag(value)
          }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Audio Fade Out")
              .font(.subheadline)
              .fontWeight(.medium)
            Text("Gentle fade before alerting")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Alarm")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Sleep Timer and Alarm")
    .sheet(isPresented: $isEditingCustomDuration) {
      CustomDurationSheet(totalMinutes: customTotalMinutes) { totalMinutes in
        setCustomDuration(totalMinutes: totalMinutes)
      }
    }
  }

  @ViewBuilder
  private func durationMenuButton(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      if isSelected {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }

  private func durationLabel(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }

  private func chapterLabel(_ count: Int) -> String {
    count == 1 ? String(localized: "End of chapter") : String(localized: "End of \(count) chapters")
  }

  private func fadeLabel(_ value: Double) -> String {
    if value == 0 { return String(localized: "Off") }
    return Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated))
  }

  private func alarmFadeLabel(_ value: Double) -> String {
    if value == 0 {
      return String(localized: "No Fade")
    }
    return Duration.seconds(value).formatted()
  }
}

private struct AutoTimerTriggerRow: View {
  @Binding var selection: AutoTimerTrigger

  var body: some View {
    HStack(spacing: 8) {
      ForEach(AutoTimerTrigger.allCases, id: \.self) { trigger in
        Button {
          selection = trigger
        } label: {
          Text(trigger.displayText)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(selection == trigger ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == trigger ? Color.accentColor : Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct TimerPauseBehaviorRow: View {
  @Binding var selection: TimerPauseBehavior

  var body: some View {
    HStack(spacing: 8) {
      ForEach(TimerPauseBehavior.allCases, id: \.self) { behavior in
        Button {
          selection = behavior
        } label: {
          Text(behavior.displayText)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(selection == behavior ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == behavior ? Color.accentColor : Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct CustomDurationSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var hours: Int
  @State private var minutes: Int

  private let onSet: (Int) -> Void

  #if os(iOS) && !targetEnvironment(macCatalyst)
  private let sheetHeight: CGFloat = 370
  #else
  private let sheetHeight: CGFloat = 260
  #endif

  init(totalMinutes: Int, onSet: @escaping (Int) -> Void) {
    _hours = State(initialValue: totalMinutes / 60)
    _minutes = State(initialValue: totalMinutes % 60)
    self.onSet = onSet
  }

  var body: some View {
    VStack(spacing: 0) {
      Text("Custom time")
        .font(.title3)
        .fontWeight(.semibold)
        .padding(.top, 28)

      Spacer(minLength: 12)

      HStack {
        HStack {
          Picker("Hours", selection: $hours) {
            ForEach(0..<24, id: \.self) { value in
              Text("\(value)").tag(value)
            }
          }
          #if os(iOS) && !targetEnvironment(macCatalyst)
          .pickerStyle(.wheel)
          #else
          .pickerStyle(.menu)
          #endif

          Text(hours == 1 ? "hour" : "hours")
            .font(.subheadline)
        }

        HStack {
          Picker("Minutes", selection: $minutes) {
            let range = hours > 0 ? 0..<60 : 1..<60
            ForEach(range, id: \.self) { value in
              Text("\(value)").tag(value)
            }
          }
          #if os(iOS) && !targetEnvironment(macCatalyst)
          .pickerStyle(.wheel)
          #else
          .pickerStyle(.menu)
          #endif

          Text(minutes == 1 ? "min" : "mins")
            .font(.subheadline)
        }
      }
      .padding(.horizontal, 20)
      #if os(iOS) && !targetEnvironment(macCatalyst)
      .frame(height: 150)
      #endif
      .onChange(of: hours) { _, newValue in
        if newValue == 0, minutes == 0 { minutes = 1 }
      }

      Spacer(minLength: 12)

      Button {
        onSet(hours * 60 + minutes)
        dismiss()
      } label: {
        Text("Set").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.horizontal, 20)
      .padding(.bottom, 24)
    }
    .frame(maxHeight: .infinity)
    .presentationDetents([.height(sheetHeight)])
    .presentationDragIndicator(.visible)
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
