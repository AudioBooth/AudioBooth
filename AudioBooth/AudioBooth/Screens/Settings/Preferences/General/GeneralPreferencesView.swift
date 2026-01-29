import SwiftUI

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

        Picker("Color Scheme", selection: $preferences.colorScheme) {
          ForEach(ColorSchemeMode.allCases, id: \.rawValue) { mode in
            Text(mode.displayText).tag(mode)
          }
        }
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
