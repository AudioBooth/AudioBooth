import SwiftUI

struct GeneralPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        Toggle("Auto-Download Books", isOn: $preferences.autoDownloadBooks)
          .bold()

        Toggle("Remove Download on Completion", isOn: $preferences.removeDownloadOnCompletion)
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
