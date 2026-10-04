import SwiftUI

struct GeneralPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var preferences = UserPreferences.shared
  @ObservedObject private var iconModel = AppIconPickerViewModel.shared

  var body: some View {
    Form {
      Section("Behavior") {
        Toggle(isOn: $preferences.hapticsEnabled) {
          PreferenceRow(
            systemImage: "bolt",
            tint: .orange,
            title: "Haptic Feedback",
            subtitle: "Subtle vibrations on controls"
          )
        }
        .listRowBackground(theme.colors.background.card)
      }

      Section("Appearance") {
        #if !targetEnvironment(macCatalyst)
        AppIconPickerView()
          .listRowBackground(theme.colors.background.card)
        #endif

        ThemePickerView()
          .listRowBackground(theme.colors.background.card)

        AccentColorPickerView()
          .listRowBackground(theme.colors.background.card)

        ColorSchemePickerView()
          .listRowBackground(theme.colors.background.card)

        NavigationLink {
          CardPreferencesView()
        } label: {
          PreferenceRow(
            systemImage: "rectangle.on.rectangle",
            tint: .teal,
            title: "Cards",
            subtitle: "Layout, aspect ratio, and corner radius"
          )
        }
        .listRowBackground(theme.colors.background.card)

        #if targetEnvironment(macCatalyst)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Display Scale")
              .font(.subheadline)
              .bold()
            Spacer()
            Text(preferences.displayScale, format: .percent.precision(.fractionLength(0)))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Slider(value: $preferences.displayScale, in: 0.8...2.0, step: 0.05)
        }
        .listRowBackground(theme.colors.background.card)
        #endif

        if preferences.accentColor != nil || preferences.colorScheme != .auto || iconModel.currentIcon != .default
          || preferences.appTheme != .sepia
        {
          Button {
            preferences.accentColor = nil
            preferences.colorScheme = .auto
            preferences.appTheme = .sepia
            iconModel.setAlternateAppIcon(icon: .default)
          } label: {
            Text("Reset Appearance to Default")
              .font(.subheadline)
              .bold()
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .center)
          }
          .buttonStyle(.plain)
          .listRowBackground(theme.colors.background.card)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page.ignoresSafeArea())
    .navigationTitle("General")
  }

}

#Preview {
  NavigationStack {
    GeneralPreferencesView()
  }
}
