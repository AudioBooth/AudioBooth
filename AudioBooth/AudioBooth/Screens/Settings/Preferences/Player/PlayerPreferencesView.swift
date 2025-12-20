import SwiftUI

struct PlayerPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text("Skip forward and back".uppercased())
            .bold()

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
      }
      .listRowSeparator(.hidden)
      .listSectionSpacing(.custom(12))

      Section {
        VStack(alignment: .leading) {
          Text("Timer".uppercased())
            .bold()

          Text("Extends timer when you shake your phone or resume playing on your headphones.")
        }
        .font(.caption)

        Toggle("Shake to extend", isOn: $preferences.shakeToExtendTimer)
          .font(.subheadline)
          .bold()

        Picker("Audio Fade Out", selection: $preferences.timerFadeOut) {
          Text("Off").tag(0.0)
          Text("15s").tag(15.0)
          Text("30s").tag(30.0)
          Text("60s").tag(60.0)
        }
        .font(.subheadline)
        .bold()
      }
      .listRowSeparator(.hidden)
      .listSectionSpacing(.custom(12))

      Section {
        VStack(alignment: .leading) {
          Text("Lock Screen Controls".uppercased())
            .bold()

          Text("Configure how the lock screen playback controls behave.")
        }
        .font(.caption)

        Picker("Skip by", selection: $preferences.lockScreenNextPreviousUsesChapters) {
          Text("Seconds").tag(false)
          Text("Chapter").tag(true)
        }
        .font(.subheadline)
        .bold()

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
