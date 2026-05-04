import SwiftUI

struct GeneralPreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared
  @StateObject private var iconModel = AppIconPickerViewModel()

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $preferences.openPlayerOnLaunch) {
          Text("Open Player on Launch")
            .font(.subheadline)
            .bold()
        }

        Toggle(isOn: $preferences.hapticsEnabled) {
          Text("Haptic Feedback")
            .font(.subheadline)
            .bold()
        }
      }

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

        #if targetEnvironment(macCatalyst)
        Stepper(value: $preferences.displayScale, in: 0.8...2.0, step: 0.05) {
          HStack {
            Text("Display Scale")
              .font(.subheadline)
              .bold()
            Spacer()
            Text(preferences.displayScale, format: .percent.precision(.fractionLength(0)))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        #endif
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
