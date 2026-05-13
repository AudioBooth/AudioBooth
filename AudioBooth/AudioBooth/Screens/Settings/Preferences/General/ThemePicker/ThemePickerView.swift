import Combine
import SwiftUI

struct ThemePickerView: View {
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Theme")
        .font(.subheadline)
        .fontWeight(.medium)
      Row(selection: $preferences.appTheme)
    }
  }
}

extension ThemePickerView {
  struct Row: View {
    @Binding var selection: AppTheme

    var body: some View {
      HStack(spacing: 12) {
        ForEach(AppTheme.allCases, id: \.self) { theme in
          Swatch(theme: theme, isSelected: selection == theme) {
            selection = theme
          }
        }
      }
    }
  }
}

extension ThemePickerView.Row {
  struct Swatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.clear)
            .overlay(background)
            .overlay(card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .padding(4)
            .overlay(
              RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )

          Text(theme.displayText)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(theme.displayText))
    }

    private var background: some View {
      HStack(spacing: 0) {
        theme.colors.background.page.colorScheme(.light)
        theme.colors.background.page.colorScheme(.dark)
      }
    }

    private var card: some View {
      GeometryReader { geo in
        HStack(spacing: 0) {
          theme.colors.background.card.colorScheme(.light)
          theme.colors.background.card.colorScheme(.dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: geo.size.width * 0.55, height: geo.size.height * 0.45)
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
      }
    }
  }
}

#Preview {
  ScrollView {
    ThemePickerView()
      .padding()
      .background(AppTheme.sepia.colors.background.card)
      .padding()
      .background(AppTheme.sepia.colors.background.page)
  }
}
