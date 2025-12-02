import SwiftUI

struct GeneralPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        Toggle("Auto-Download Books", isOn: $preferences.autoDownloadBooks)
          .font(.subheadline)
          .bold()

        Toggle("Remove Download on Completion", isOn: $preferences.removeDownloadOnCompletion)
          .font(.subheadline)
          .bold()
      }
    }
    .navigationTitle("General")
  }
}

#Preview {
  NavigationStack {
    GeneralPreferencesView()
  }
}
