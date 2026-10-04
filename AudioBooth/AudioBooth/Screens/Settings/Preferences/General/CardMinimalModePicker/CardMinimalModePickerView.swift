import Combine
import SwiftUI

struct CardMinimalModePickerView: View {
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Card Style")
        .font(.subheadline)
        .fontWeight(.medium)

      HStack(spacing: 12) {
        Swatch(isMinimal: true, isSelected: preferences.cardMinimalMode) {
          preferences.cardMinimalMode = true
        }
        Swatch(isMinimal: false, isSelected: !preferences.cardMinimalMode) {
          preferences.cardMinimalMode = false
        }
      }
    }
  }
}

extension CardMinimalModePickerView {
  struct Swatch: View {
    @Environment(\.appTheme) var theme
    let isMinimal: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 6) {
            cover

            if !isMinimal {
              VStack(spacing: 2) {
                Text("Foundation")
                  .font(.caption2)
                  .fontWeight(.medium)
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                Text("Isaac Asimov")
                  .font(.system(size: 9))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(10)
          .background(theme.colors.background.page.ignoresSafeArea())
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .padding(4)
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
          )

          Text(label)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(label))
    }

    private var label: LocalizedStringResource {
      isMinimal ? "Minimal" : "Standard"
    }

    private var cover: some View {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: 90, height: 90)
    }
  }
}

#Preview {
  ScrollView {
    CardMinimalModePickerView()
      .padding()
      .background(Color.Sepia.Background.card)
      .padding()
      .background(Color.Sepia.Background.page)
  }
}
