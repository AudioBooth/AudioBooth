import SwiftUI

extension AutoDownloadMode: Identifiable {
  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .off:
      return "Off"
    case .wifiOnly:
      return "Wi-Fi Only"
    case .wifiAndCellular:
      return "Wi-Fi & Cellular"
    }
  }
}

struct GeneralPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared
  @StateObject private var iconModel = AppIconPickerViewModel()

  var body: some View {
    Form {
      Section("Appearance") {
        NavigationLink {
          AppIconPickerView(model: iconModel)
        } label: {
          HStack {
            Text("App Icon")
              .font(.subheadline)
              .bold()
            Spacer()
            Image(iconModel.currentIcon.previewImageName)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 29, height: 29)
              .cornerRadius(5)
          }
        }

        ColorPicker(
          "Accent Color",
          selection: Binding(
            get: { preferences.accentColor ?? .accentColor },
            set: { preferences.accentColor = $0 }
          ),
          supportsOpacity: false
        )
        .font(.subheadline)
        .bold()

        if preferences.accentColor != nil {
          Button("Reset to Default") {
            preferences.accentColor = nil
          }
          .font(.subheadline)
          .foregroundStyle(.red)
        }
      }

      Section {
        Picker("Auto-Download Books", selection: $preferences.autoDownloadBooks) {
          ForEach(AutoDownloadMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
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
