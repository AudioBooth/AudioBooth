import SwiftUI

struct UpNextPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $preferences.autoPlayNextInQueue) {
          PreferenceRow(
            systemImage: "list.bullet",
            tint: .teal,
            title: "Auto-play Next in Queue",
            subtitle: "Play the next item you queued up"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Queue")
      } footer: {
        Text("The queue always plays first. The options below apply once it is empty.")
          .font(.caption)
      }

      Section {
        Toggle(isOn: $preferences.continueNextInSeries) {
          PreferenceRow(
            systemImage: "books.vertical",
            tint: .indigo,
            title: "Next Book in Series",
            subtitle: "Automatically play the next book in the series"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.continueNextDownloadedBook) {
          PreferenceRow(
            systemImage: "arrow.down.circle",
            tint: .indigo,
            title: "Next Downloaded Book",
            subtitle: "Automatically play the next downloaded book"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.continueNextPodcastEpisode) {
          PreferenceRow(
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .indigo,
            title: "Next Podcast Episode",
            subtitle: "Automatically play the next podcast episode"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Smart Continue")
      } footer: {
        Text("Items you already finished are skipped. When nothing is left to play, the player closes.")
          .font(.caption)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Up Next")
  }
}

#Preview {
  NavigationStack {
    UpNextPreferencesView()
  }
}
