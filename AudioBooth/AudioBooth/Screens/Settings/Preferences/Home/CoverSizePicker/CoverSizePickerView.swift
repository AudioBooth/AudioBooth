import Combine
import SwiftUI

struct CoverSizePickerView: View {
  @Binding var selection: ContinueSectionSize

  var body: some View {
    HStack(spacing: 12) {
      ForEach(ContinueSectionSize.allCases, id: \.self) { size in
        Swatch(size: size, isSelected: selection == size) {
          selection = size
        }
      }
    }
  }
}

extension CoverSizePickerView {
  struct Swatch: View {
    @Environment(\.appTheme) var theme
    let size: ContinueSectionSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
              LinearGradient(
                colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: previewSide, height: previewSide)

          Text(size.displayText)
            .font(.subheadline)
            .fontWeight(isSelected ? .medium : .regular)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : theme.colors.background.card)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(size.displayText))
    }

    private var previewSide: CGFloat {
      switch size {
      case .default: 36
      case .large: 52
      case .extraLarge: 68
      }
    }
  }
}

#Preview {
  struct Wrapper: View {
    @State private var selection: ContinueSectionSize = .large
    var body: some View {
      ScrollView {
        CoverSizePickerView(selection: $selection)
          .padding()
          .background(Color.Sepia.Background.page)
      }
    }
  }
  return Wrapper()
}
