import Combine
import SwiftUI

struct ColorSchemePickerView: View {
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Color Scheme")
        .font(.subheadline)
        .fontWeight(.medium)
      Row(selection: $preferences.colorScheme)
    }
  }
}

extension ColorSchemePickerView {
  struct Row: View {
    @Binding var selection: ColorSchemeMode

    private let order: [ColorSchemeMode] = [.light, .dark, .auto]

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
}

extension ColorSchemePickerView.Row {
  struct Swatch: View {
    @Environment(\.appTheme) var theme
    let mode: ColorSchemeMode
    let isSelected: Bool
    let action: () -> Void

    private static let barColor = Color(white: 0.55)

    var body: some View {
      Button(action: action) {
        VStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.clear)
            .overlay(background)
            .overlay(bar)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .padding(4)
            .overlay(
              RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )

          Text(mode.displayText)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(mode.displayText))
    }

    @ViewBuilder
    private var background: some View {
      switch mode {
      case .light:
        theme.colors.background.page.colorScheme(.light)
      case .dark:
        theme.colors.background.page.colorScheme(.dark)
      case .auto:
        HStack(spacing: 0) {
          theme.colors.background.page.colorScheme(.light)
          theme.colors.background.page.colorScheme(.dark)
        }
      }
    }

    private var bar: some View {
      GeometryReader { geo in
        let width = geo.size.width * 0.32
        Capsule()
          .fill(Self.barColor)
          .frame(width: width, height: 4)
          .position(x: geo.size.width / 2, y: geo.size.height / 2)
      }
    }
  }
}

#Preview {
  ScrollView {
    ColorSchemePickerView()
      .padding()
      .background(Color.Sepia.Background.card)
      .padding()
      .background(Color.Sepia.Background.page)
  }
}
