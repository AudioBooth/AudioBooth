import SwiftUI

struct PlaybackDisplayPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $preferences.showFullBookDuration) {
          PreferenceRow(
            systemImage: "clock",
            tint: .blue,
            title: "Use Book Duration",
            subtitle: "Show whole-book time instead of chapter"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.showBookProgressBar) {
          PreferenceRow(
            systemImage: "slider.horizontal.below.rectangle",
            tint: .orange,
            title: "Supplementary Progress Bar",
            subtitle: "Show book progress under chapter bar"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.hideChapterSkipButtons) {
          PreferenceRow(
            systemImage: "eye.slash",
            tint: .purple,
            title: "Hide Chapter Skip Buttons",
            subtitle: "Cleaner player UI"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Time & Progress")
      }

      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text("Lock Player Orientation")
            .font(.subheadline)
            .fontWeight(.medium)
          OrientationPicker(selection: $preferences.playerOrientation)
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Orientation")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Playback Display")
  }
}

private struct OrientationPicker: View {
  @Binding var selection: PlayerOrientation

  private let order: [PlayerOrientation] = [.auto, .portrait, .landscape]

  var body: some View {
    HStack(spacing: 12) {
      ForEach(order, id: \.self) { mode in
        Swatch(mode: mode, isSelected: selection == mode) {
          selection = mode
        }
      }
    }
  }
}

extension OrientationPicker {
  struct Swatch: View {
    let mode: PlayerOrientation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .overlay(icon)
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )

          Text(mode.displayText)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
      switch mode {
      case .auto:
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
      case .portrait:
        RoundedRectangle(cornerRadius: 4)
          .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.5), lineWidth: 1.5)
          .frame(width: 26, height: 38)
      case .landscape:
        RoundedRectangle(cornerRadius: 4)
          .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.5), lineWidth: 1.5)
          .frame(width: 38, height: 26)
      }
    }
  }
}

#Preview {
  NavigationStack {
    PlaybackDisplayPreferencesView()
  }
}
