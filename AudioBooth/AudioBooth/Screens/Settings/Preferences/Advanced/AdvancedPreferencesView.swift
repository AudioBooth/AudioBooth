import SwiftUI

struct AdvancedPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text("NFC Tag Writing".uppercased())
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
    .navigationTitle("Advanced")
  }
}

#Preview {
  NavigationStack {
    AdvancedPreferencesView()
  }
}
