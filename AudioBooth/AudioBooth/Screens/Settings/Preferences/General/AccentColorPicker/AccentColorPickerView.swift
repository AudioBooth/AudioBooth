import Combine
import SwiftUI

struct AccentColorPickerView: View {
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Accent Color")
        .font(.subheadline)
        .fontWeight(.medium)
      Row(
        selection: Binding(
          get: { preferences.accentColor ?? .accentColor },
          set: { preferences.accentColor = $0 }
        )
      )
    }
  }
}

extension AccentColorPickerView {
  struct Row: View {
    @Binding var selection: Color

    let presets: [Preset] = [
      .init(name: "Orange", color: Color(.displayP3, red: 0.945, green: 0.651, blue: 0.255)),
      .init(name: "Blue", color: Color(.displayP3, red: 0.20, green: 0.50, blue: 0.90)),
      .init(name: "Green", color: Color(.displayP3, red: 0.30, green: 0.80, blue: 0.50)),
      .init(name: "Pink", color: Color(.displayP3, red: 1.00, green: 0.40, blue: 0.70)),
      .init(name: "Purple", color: Color(.displayP3, red: 0.70, green: 0.30, blue: 0.85)),
      .init(name: "Red", color: Color(.displayP3, red: 0.95, green: 0.35, blue: 0.40)),
      .init(name: "Teal", color: Color(.displayP3, red: 0.20, green: 0.85, blue: 0.80)),
      .init(name: "Black", color: .black),
    ]

    var body: some View {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(presets) { preset in
            Swatch(
              color: preset.color,
              isSelected: matches(preset.color)
            ) {
              selection = preset.color
            }
          }
          ColorPicker(selection: $selection, supportsOpacity: false) {
            EmptyView()
          }
          .labelsHidden()
        }
        .padding(.horizontal, 16)
      }
      .padding(.horizontal, -16)
    }

    func matches(_ color: Color) -> Bool {
      UIColor(color).cgColor.components == UIColor(selection).cgColor.components
    }
  }
}

extension AccentColorPickerView.Row {
  struct Preset: Identifiable {
    let name: LocalizedStringKey
    let color: Color
    var id: String { "\(color)" }
  }

  struct Swatch: View {
    @Environment(\.appTheme) var theme
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        ZStack {
          if isSelected {
            Circle()
              .fill(color)
          }

          Circle()
            .fill(color)
            .stroke(theme.colors.background.card, lineWidth: 2)
            .frame(width: 20, height: 20)
        }
        .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
    }
  }
}

#Preview {
  ScrollView {
    AccentColorPickerView()
      .padding()
      .background(Color.Sepia.Background.card)
      .padding()
      .background(Color.Sepia.Background.page)
  }
}
