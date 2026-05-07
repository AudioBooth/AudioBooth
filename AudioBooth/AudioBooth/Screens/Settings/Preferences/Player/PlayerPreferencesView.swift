import SwiftUI

struct TimePicker: View {
  @Binding var minutesSinceMidnight: Int

  private var date: Binding<Date> {
    Binding(
      get: {
        let calendar = Calendar.current
        let now = Date()
        let hours = minutesSinceMidnight / 60
        let minutes = minutesSinceMidnight % 60
        return calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: now) ?? now
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

struct PlayerPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  @State private var allControls: [PlayerControl] = []
  @State private var enabledControls: Set<PlayerControl> = []

  var body: some View {
    Form {
      Section {
        List {
          ForEach(allControls) { control in
            HStack {
              Text(control.displayName)
                .font(.subheadline)
                .bold()
              Spacer()
              Toggle(isOn: controlBinding(for: control)) {}
            }
          }
          .onMove { source, destination in
            allControls.move(fromOffsets: source, toOffset: destination)
          }
        }
      } header: {
        Text("Controls")
      } footer: {
        Text("Drag to reorder. Disabled controls move to the player menu.")
          .font(.caption)
      }

      playerPreferencesForm
    }
    .navigationTitle("Player")
    .environment(\.editMode, .constant(.active))
    .onAppear(perform: loadControls)
    .onDisappear(perform: saveControls)
  }

  private func controlBinding(for control: PlayerControl) -> Binding<Bool> {
    Binding(
      get: { enabledControls.contains(control) },
      set: { isEnabled in
        if isEnabled {
          enabledControls.insert(control)
        } else {
          enabledControls.remove(control)
        }
      }
    )
  }

  private func loadControls() {
    let stored = preferences.playerControls
    let storedSet = Set(stored)
    let disabled = PlayerControl.allCases.filter { !storedSet.contains($0) }
    allControls = stored + disabled
    enabledControls = storedSet
  }

  private func saveControls() {
    preferences.playerControls = allControls.filter { enabledControls.contains($0) }
  }

  private var autoTimerModeAccessibilityValue: String {
    switch preferences.autoTimerMode {
    case .off: String(localized: "Off")
    case .duration(let seconds):
      Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .wide))
    case .chapters(let count): String(localized: "End of \(count) \(count == 1 ? "chapter" : "chapters")")
    }
  }

  @ViewBuilder
  private var playerPreferencesForm: some View {
    Section {
      VStack(alignment: .leading) {
        Text("Skip forward and back")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Choose how far to skip forward and back while listening.")
      }
      .font(.caption)

      DisclosureGroup(
        content: {
          HStack {
            VStack(spacing: .zero) {
              Text("Back").bold()

              Picker("Back", selection: $preferences.skipBackwardInterval) {
                ForEach([10.0, 15.0, 30.0, 60.0, 90.0], id: \.self) { seconds in
                  Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
                    .tag(seconds)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: .zero) {
              Text("Forward").bold()

              Picker("Forward", selection: $preferences.skipForwardInterval) {
                ForEach([10.0, 15.0, 30.0, 60.0, 90.0], id: \.self) { seconds in
                  Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
                    .tag(seconds)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .center)
          }
          .pickerStyle(.wheel)
          .labelsHidden()
        },
        label: {
          Text(
            "Back \(Int(preferences.skipBackwardInterval))s Forward \(Int(preferences.skipForwardInterval))s"
          )
          .font(.subheadline)
          .bold()
        }
      )
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Smart Rewind")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Rewind after being paused for a configurable duration or after audio interruptions.")
      }
      .font(.caption)

      VStack(alignment: .leading) {
        Picker("Minimum Pause", selection: $preferences.smartRewindAfterPauseThreshold) {
          Text("Any").tag(0.0)
          ForEach([60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0], id: \.self) { seconds in
            Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .abbreviated)))
              .tag(seconds)
          }
        }
        .accessibilityLabel("Smart Rewind Pause Threshold")
        .accessibilityValue(
          preferences.smartRewindAfterPauseThreshold == 0
            ? "Any pause"
            : Duration.seconds(preferences.smartRewindAfterPauseThreshold)
              .formatted(.units(allowed: [.minutes], width: .wide))
        )

        Picker("Rewind By", selection: $preferences.smartRewindInterval) {
          Text("Off").tag(0.0)
          ForEach([5.0, 10.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0], id: \.self) { seconds in
            Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
              .tag(seconds)
          }
        }
        .accessibilityLabel("Smart Rewind After Pause Duration")
        .accessibilityValue(
          preferences.smartRewindInterval == 0 ? "Off" : "\(Int(preferences.smartRewindInterval)) seconds"
        )
      }
      .font(.subheadline)
      .bold()

      Picker("On Interruption", selection: $preferences.smartRewindOnInterruptionInterval) {
        Text("Off").tag(0.0)
        ForEach([5.0, 10.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0], id: \.self) { seconds in
          Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
            .tag(seconds)
        }
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Smart Rewind On Interruption Duration")
      .accessibilityValue(
        preferences.smartRewindOnInterruptionInterval == 0
          ? "Off" : "\(Int(preferences.smartRewindOnInterruptionInterval)) seconds"
      )
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Timer")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Shake your phone to reset the timer during playback.")
      }
      .font(.caption)

      Picker("Shake Sensitivity to Reset", selection: $preferences.shakeSensitivity) {
        Text("Off").tag(ShakeSensitivity.off)
        Text("Very Low").tag(ShakeSensitivity.veryLow)
        Text("Low").tag(ShakeSensitivity.low)
        Text("Medium").tag(ShakeSensitivity.medium)
        Text("High").tag(ShakeSensitivity.high)
        Text("Very High").tag(ShakeSensitivity.veryHigh)
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Shake to Reset Timer Sensitivity")
      .accessibilityValue(preferences.shakeSensitivity.displayText)

      Picker("Audio Fade Out", selection: $preferences.timerFadeOut) {
        Text("Off").tag(0.0)
        ForEach([15.0, 30.0, 60.0], id: \.self) { seconds in
          Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
            .tag(seconds)
        }
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Timer Audio Fade Out")
      .accessibilityValue(
        preferences.timerFadeOut == 0 ? "Off" : "\(Int(preferences.timerFadeOut)) seconds"
      )
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Automatic Sleep Timer")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text(
          "Automatically start a sleep timer when playing during a specific time window."
        )
      }
      .font(.caption)

      Picker("Sleep Timer", selection: $preferences.autoTimerMode) {
        Text("Off").tag(AutoTimerMode.off)
        Divider()
        ForEach([300.0, 600.0, 900.0, 1200.0, 1800.0, 2700.0, 3600.0], id: \.self) { seconds in
          Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .abbreviated)))
            .tag(AutoTimerMode.duration(seconds))
        }
        Divider()
        Text("End of chapter").tag(AutoTimerMode.chapters(1))
        Text("End of 2 chapters").tag(AutoTimerMode.chapters(2))
        Text("End of 3 chapters").tag(AutoTimerMode.chapters(3))
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Auto Timer Mode")
      .accessibilityValue(autoTimerModeAccessibilityValue)

      if preferences.autoTimerMode != .off {
        HStack {
          Text("Start Time")
          Spacer()
          TimePicker(minutesSinceMidnight: $preferences.autoTimerWindowStart)
        }
        .font(.subheadline)
        .bold()

        HStack {
          Text("End Time")
          Spacer()
          TimePicker(minutesSinceMidnight: $preferences.autoTimerWindowEnd)
        }
        .font(.subheadline)
        .bold()
      }
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Lock Screen Controls")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Configure how the lock screen playback controls behave.")
      }
      .font(.caption)

      Picker("Skip By", selection: $preferences.lockScreenNextPreviousUsesChapters) {
        Text("Seconds").tag(false)
        Text("Chapter").tag(true)
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Lock Screen Next/Previous Buttons")
      .accessibilityValue(preferences.lockScreenNextPreviousUsesChapters ? "Chapter" : "Seconds")

      Toggle(
        "Allow Playback Position Change",
        isOn: $preferences.lockScreenAllowPlaybackPositionChange
      )
      .font(.subheadline)
      .bold()
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Narration Speed")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Set your default narration speed for new books.")
      }
      .font(.caption)

      Stepper(value: $preferences.defaultPlaybackSpeed, in: 0.5...3.5, step: 0.05) {
        HStack {
          Text("Default")
            .font(.subheadline)
            .bold()
          Spacer()
          Text(verbatim: "\(preferences.defaultPlaybackSpeed.formatted(.number.precision(.fractionLength(2))))×")
            .foregroundStyle(.secondary)
        }
      }
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Playback Speed Adjustments")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Configure how time displays are affected by playback speed.")
      }
      .font(.caption)

      Toggle("Adjusts Time Remaining", isOn: $preferences.timeRemainingAdjustsWithSpeed)
        .font(.subheadline)
        .bold()

      Toggle("Adjusts Chapter Progression", isOn: $preferences.chapterProgressionAdjustsWithSpeed)
        .font(.subheadline)
        .bold()
    }
    .listRowSeparator(.hidden)

    Section {
      VStack(alignment: .leading) {
        Text("Playback Display")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Configure how playback and progress is displayed for books with chapters.")
      }
      .font(.caption)

      Toggle("Use Book Duration (Instead of Chapter)", isOn: $preferences.showFullBookDuration)
        .font(.subheadline)
        .bold()

      Toggle("Show Supplementary Book Progress Bar", isOn: $preferences.showBookProgressBar)
        .font(.subheadline)
        .bold()

      Toggle("Hide Chapter Skip Buttons", isOn: $preferences.hideChapterSkipButtons)
        .font(.subheadline)
        .bold()
    }
    .listRowSeparator(.hidden)
    .listSectionSpacing(.custom(12))

    Section {
      VStack(alignment: .leading) {
        Text("Orientation Lock")
          .textCase(.uppercase)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text("Lock the player screen orientation.")
      }
      .font(.caption)

      Picker("Orientation", selection: $preferences.playerOrientation) {
        Text("Auto").tag(PlayerOrientation.auto)
        Text("Portrait").tag(PlayerOrientation.portrait)
        Text("Landscape").tag(PlayerOrientation.landscape)
      }
      .font(.subheadline)
      .bold()
      .accessibilityLabel("Player Orientation")
      .accessibilityValue(preferences.playerOrientation.displayText)
    }
    .listRowSeparator(.hidden)
  }
}

#Preview {
  NavigationStack {
    PlayerPreferencesView()
  }
}
