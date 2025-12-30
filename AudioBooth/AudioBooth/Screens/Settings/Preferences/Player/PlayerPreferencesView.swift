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
    DatePicker(
      "",
      selection: date,
      displayedComponents: .hourAndMinute
    )
    .labelsHidden()
  }
}

struct PlayerPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text("Skip forward and back".uppercased())
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
                  Text("10s").tag(10.0)
                  Text("15s").tag(15.0)
                  Text("30s").tag(30.0)
                  Text("60s").tag(60.0)
                  Text("90s").tag(90.0)
                }
              }
              .frame(maxWidth: .infinity, alignment: .center)

              VStack(spacing: .zero) {
                Text("Forward").bold()

                Picker("Forward", selection: $preferences.skipForwardInterval) {
                  Text("10s").tag(10.0)
                  Text("15s").tag(15.0)
                  Text("30s").tag(30.0)
                  Text("60s").tag(60.0)
                  Text("90s").tag(90.0)
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
          Text("Smart Rewind".uppercased())
            .bold()
            .accessibilityAddTraits(.isHeader)

          Text("Rewind after being paused for 10 minutes.")
        }
        .font(.caption)

        Picker("Back", selection: $preferences.smartRewindInterval) {
          Text("Off").tag(0.0)
          Text("5s").tag(5.0)
          Text("10s").tag(10.0)
          Text("15s").tag(15.0)
          Text("30s").tag(30.0)
          Text("45s").tag(45.0)
          Text("60s").tag(60.0)
          Text("75s").tag(75.0)
          Text("90s").tag(90.0)
        }
        .font(.subheadline)
        .bold()
        .accessibilityLabel("Smart Rewind Duration")
      }
      .listRowSeparator(.hidden)
      .listSectionSpacing(.custom(12))

      Section {
        VStack(alignment: .leading) {
          Text("Timer".uppercased())
            .bold()
            .accessibilityAddTraits(.isHeader)

          Text("Shake your phone to reset the timer during playback.")
        }
        .font(.caption)

        Picker("Shake to Reset", selection: $preferences.shakeSensitivity) {
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

        Picker("Audio Fade Out", selection: $preferences.timerFadeOut) {
          Text("Off").tag(0.0)
          Text("15s").tag(15.0)
          Text("30s").tag(30.0)
          Text("60s").tag(60.0)
        }
        .font(.subheadline)
        .bold()
        .accessibilityLabel("Timer Audio Fade Out")
      }
      .listRowSeparator(.hidden)
      .listSectionSpacing(.custom(12))

      Section {
        VStack(alignment: .leading) {
          Text("Automatic Sleep Timer".uppercased())
            .bold()
            .accessibilityAddTraits(.isHeader)

          Text(
            "Automatically start a sleep timer when playing during a specific time window."
          )
        }
        .font(.caption)

        Picker("Sleep Timer", selection: $preferences.autoTimerDuration) {
          Text("Off").tag(0.0)
          Text("5 min").tag(300.0)
          Text("10 min").tag(600.0)
          Text("15 min").tag(900.0)
          Text("20 min").tag(1200.0)
          Text("30 min").tag(1800.0)
          Text("45 min").tag(2700.0)
          Text("60 min").tag(3600.0)
        }
        .font(.subheadline)
        .bold()
        .accessibilityLabel("Auto Timer Duration")

        if preferences.autoTimerDuration > 0 {
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
          Text("Lock Screen Controls".uppercased())
            .bold()
            .accessibilityAddTraits(.isHeader)

          Text("Configure how the lock screen playback controls behave.")
        }
        .font(.caption)

        Picker("Skip by", selection: $preferences.lockScreenNextPreviousUsesChapters) {
          Text("Seconds").tag(false)
          Text("Chapter").tag(true)
        }
        .font(.subheadline)
        .bold()
        .accessibilityLabel("Lock Screen Next/Previous Buttons")

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
          Text("Playback Speed Adjustments".uppercased())
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
          Text("Progress Display".uppercased())
            .bold()
            .accessibilityAddTraits(.isHeader)

          Text("Choose how playback progress is displayed.")
        }
        .font(.caption)

        Toggle("Show Full Book Duration", isOn: $preferences.showFullBookDuration)
          .font(.subheadline)
          .bold()
      }
      .listRowSeparator(.hidden)
    }
    .navigationTitle("Player")
  }
}

#Preview {
  NavigationStack {
    PlayerPreferencesView()
  }
}
