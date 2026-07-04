import CoreNFC
import SwiftUI

struct AdvancedPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $preferences.iCloudSyncEnabled) {
          PreferenceRow(
            systemImage: "icloud.fill",
            tint: .blue,
            title: "iCloud Sync"
          )
        }
        .listRowBackground(theme.colors.background.card)
        .onChange(of: preferences.iCloudSyncEnabled) { _, enabled in
          if enabled {
            preferences.syncToCloud()
            PlayerManager.shared.syncQueueToCloud()
          } else {
            preferences.purgeCloud()
            PlayerManager.shared.purgeQueueFromCloud()
          }
        }
      } header: {
        Text("iCloud")
      } footer: {
        Text("Sync your preferences and Playing Next queue across all your devices using iCloud.")
          .font(.caption)
      }

      if NFCNDEFReaderSession.readingAvailable {
        Section {
          Toggle(isOn: $preferences.showNFCTagWriting) {
            PreferenceRow(
              systemImage: "wave.3.right",
              tint: .indigo,
              title: "NFC Tag Writing"
            )
          }
          .listRowBackground(theme.colors.background.card)
        } header: {
          Text("NFC")
        } footer: {
          Text("Show option in book details menu to write book information to NFC tags for quick playback access.")
            .font(.caption)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Advanced")
  }
}

#Preview {
  NavigationStack {
    AdvancedPreferencesView()
  }
}
