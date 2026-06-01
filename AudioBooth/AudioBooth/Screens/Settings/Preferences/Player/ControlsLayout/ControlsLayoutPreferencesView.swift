import SwiftUI

struct ControlsLayoutPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  @State private var enabledControls: [PlayerControl] = []
  @State private var disabledControls: [PlayerControl] = []

  var body: some View {
    Form {
      Section {
        ForEach(enabledControls) { control in
          controlRow(control)
            .listRowBackground(theme.colors.background.card)
        }
        .onMove(perform: moveEnabled)
      } header: {
        HStack {
          Text("In Player Bar")
          Spacer()
          Button("Reset", action: reset)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(nil)
        }
      } footer: {
        Text("Drag to reorder. These appear directly on the player.")
          .font(.caption)
      }

      Section {
        ForEach(disabledControls) { control in
          controlRow(control)
            .listRowBackground(theme.colors.background.card)
        }
        .onMove(perform: moveDisabled)
      } header: {
        Text("In Overflow Menu")
      } footer: {
        Text("Disabled controls move to the player's overflow menu.")
          .font(.caption)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Controls & Layout")
    .environment(\.editMode, .constant(.active))
    .onAppear(perform: load)
    .onDisappear(perform: save)
  }

  @ViewBuilder
  private func controlRow(_ control: PlayerControl) -> some View {
    HStack(spacing: 12) {
      PreferenceRow(
        systemImage: control.systemImage,
        tint: control.tint,
        title: String(localized: control.displayName)
      )
      Spacer()
      Toggle(isOn: binding(for: control)) {}
        .labelsHidden()
    }
  }

  private func binding(for control: PlayerControl) -> Binding<Bool> {
    Binding(
      get: { enabledControls.contains(control) },
      set: { isEnabledNow in
        if isEnabledNow {
          if !enabledControls.contains(control) {
            enabledControls.append(control)
            disabledControls.removeAll { $0 == control }
          }
        } else {
          if !disabledControls.contains(control) {
            disabledControls.append(control)
            enabledControls.removeAll { $0 == control }
          }
        }
      }
    )
  }

  private func moveEnabled(from source: IndexSet, to destination: Int) {
    enabledControls.move(fromOffsets: source, toOffset: destination)
  }

  private func moveDisabled(from source: IndexSet, to destination: Int) {
    disabledControls.move(fromOffsets: source, toOffset: destination)
  }

  private func load() {
    let stored = preferences.playerControls
    let storedSet = Set(stored)
    enabledControls = stored
    disabledControls = PlayerControl.allCases.filter { !storedSet.contains($0) }
  }

  private func save() {
    preferences.playerControls = enabledControls
  }

  private func reset() {
    let defaults = PlayerControl.default
    let defaultSet = Set(defaults)
    enabledControls = defaults
    disabledControls = PlayerControl.allCases.filter { !defaultSet.contains($0) }
  }
}

extension PlayerControl {
  var tint: Color {
    switch self {
    case .speed: .orange
    case .timer: .orange
    case .alarm: .red
    case .bookmarks: .purple
    case .history: .blue
    case .volume: .green
    case .equalizer: .red
    }
  }
}

#Preview {
  NavigationStack {
    ControlsLayoutPreferencesView()
  }
}
