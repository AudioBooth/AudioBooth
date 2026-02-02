import CoreNFC
import SwiftUI

struct AdvancedPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text("iCloud")
            .textCase(.uppercase)
            .bold()

          Text(
            "Sync your preferences across all your devices using iCloud."
          )
        }
        .font(.caption)

        Toggle("Enabled", isOn: $preferences.iCloudSyncEnabled)
          .font(.subheadline)
          .bold()
          .onChange(of: preferences.iCloudSyncEnabled) { _, enabled in
            if enabled {
              preferences.syncToCloud()
            } else {
              preferences.purgeCloud()
            }
          }
      }
      .listRowSeparator(.hidden)

      if NFCNDEFReaderSession.readingAvailable {
        Section {
          VStack(alignment: .leading) {
            Text("NFC Tag Writing")
              .textCase(.uppercase)
              .bold()

            Text(
              "Show option in book details menu to write book information to NFC tags for quick playback access."
            )
          }
          .font(.caption)

          Toggle("Visible", isOn: $preferences.showNFCTagWriting)
            .font(.subheadline)
            .bold()
        }
        .listRowSeparator(.hidden)
      }
    }
    .navigationTitle("Advanced")
  }
}

#Preview {
  NavigationStack {
    AdvancedPreferencesView()
  }
}
