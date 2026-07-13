import Combine
import SwiftUI

enum CardCornerRadius: String, CaseIterable {
  case none
  case small
  case medium
  case large

  var value: CGFloat {
    switch self {
    case .none: 0
    case .small: 4
    case .medium: 8
    case .large: 16
    }
  }

  var label: LocalizedStringKey {
    switch self {
    case .none: "None"
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Large"
    }
  }
}

enum CardBorderWidth: String, CaseIterable {
  case none
  case small
  case medium
  case large

  var value: CGFloat {
    switch self {
    case .none: 0
    case .small: 1
    case .medium: 2
    case .large: 3
    }
  }

  var label: LocalizedStringKey {
    switch self {
    case .none: "None"
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Large"
    }
  }
}

struct CardPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        CardPreview()
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }

      Section {
        Toggle(isOn: $preferences.cardMinimalMode) {
          PreferenceRow(
            systemImage: "rectangle.compress.vertical",
            tint: .purple,
            title: "Minimal Mode",
            subtitle: "Hide title and metadata under covers"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.cardCoverDynamicRatio) {
          PreferenceRow(
            systemImage: "aspectratio",
            tint: .blue,
            title: "Dynamic Aspect Ratio",
            subtitle: "Use each cover's natural ratio instead of a square"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.showBookSubtitle) {
          PreferenceRow(
            systemImage: "text.below.photo",
            tint: .orange,
            title: "Show Subtitle",
            subtitle: "Display the book subtitle under the title"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.dimCoverWhenCompleted) {
          PreferenceRow(
            systemImage: "checkmark.circle",
            tint: .green,
            title: "Dim Finished Books",
            subtitle: "Darken covers of completed books"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Layout")
      }

      Section {
        CornerRadiusPicker(selection: $preferences.cardCoverCornerRadius)
          .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Corner Radius")
      }

      Section {
        BorderWidthPicker(selection: $preferences.cardCoverBorderWidth)
          .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Border")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Cards")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Reset", action: reset)
          .disabled(isAtDefaults)
      }
    }
  }

  private var isAtDefaults: Bool {
    !preferences.cardMinimalMode
      && !preferences.cardCoverDynamicRatio
      && !preferences.showBookSubtitle
      && preferences.dimCoverWhenCompleted
      && preferences.cardCoverCornerRadius == .medium
      && preferences.cardCoverBorderWidth == .small
  }

  private func reset() {
    preferences.cardMinimalMode = false
    preferences.cardCoverDynamicRatio = false
    preferences.showBookSubtitle = false
    preferences.dimCoverWhenCompleted = true
    preferences.cardCoverCornerRadius = .medium
    preferences.cardCoverBorderWidth = .small
  }
}

private struct CardPreview: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  private let coverWidth: CGFloat = 120

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Preview")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.horizontal)

      HStack(alignment: .top, spacing: 16) {
        card(title: "Foundation", subtitle: "Foundation, Book 1", author: "Isaac Asimov", isDynamic: true)
        card(title: "Dune", subtitle: "Dune Chronicles 1", author: "Frank Herbert", isDynamic: false, isCompleted: true)
      }
      .padding(.horizontal)
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.background.card)
  }

  private func card(
    title: String,
    subtitle: String,
    author: String,
    isDynamic: Bool,
    isCompleted: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      cover(title: title, author: author, isDynamic: isDynamic, isCompleted: isCompleted)

      if !preferences.cardMinimalMode {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .lineLimit(1)

          if preferences.showBookSubtitle {
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Text(author)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private func cover(title: String, author: String, isDynamic: Bool, isCompleted: Bool) -> some View {
    let useDynamic = isDynamic && preferences.cardCoverDynamicRatio
    return RoundedRectangle(cornerRadius: preferences.cardCoverCornerRadius.value, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.35)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(
        width: useDynamic ? coverWidth * 2 / 3 : coverWidth,
        height: coverWidth
      )
      .overlay {
        VStack(spacing: 4) {
          Text(title)
            .font(.caption)
            .fontWeight(.semibold)
          Text(author)
            .font(.caption2)
            .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(8)
        .multilineTextAlignment(.center)
      }
      .overlay(alignment: .bottom) {
        if isCompleted {
          ProgressOverlay(progress: 1)
            .padding(4)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: preferences.cardCoverCornerRadius.value, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: preferences.cardCoverCornerRadius.value, style: .continuous)
          .strokeBorder(Color.gray.opacity(0.6), lineWidth: preferences.cardCoverBorderWidth.value)
      }
  }
}

private struct CornerRadiusPicker: View {
  @Binding var selection: CardCornerRadius

  var body: some View {
    HStack(spacing: 12) {
      ForEach(CardCornerRadius.allCases, id: \.self) { option in
        Button {
          selection = option
        } label: {
          VStack(spacing: 8) {
            CornerShape(radius: option.value)
              .stroke(
                selection == option ? Color.accentColor : Color.secondary,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
              )
              .frame(width: 28, height: 28)
              .padding(12)
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(selection == option ? Color.accentColor : .clear, lineWidth: 2)
              )

            Text(option.label)
              .font(.caption2)
              .foregroundStyle(.primary)
          }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct BorderWidthPicker: View {
  @Binding var selection: CardBorderWidth
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    HStack(spacing: 12) {
      ForEach(CardBorderWidth.allCases, id: \.self) { option in
        Button {
          selection = option
        } label: {
          VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: preferences.cardCoverCornerRadius.value, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.35)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .overlay {
                if option.value > 0 {
                  RoundedRectangle(cornerRadius: preferences.cardCoverCornerRadius.value, style: .continuous)
                    .strokeBorder(Color.gray.opacity(0.6), lineWidth: option.value)
                }
              }
              .frame(width: 44, height: 44)
              .padding(12)
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(selection == option ? Color.accentColor : .clear, lineWidth: 2)
              )

            Text(option.label)
              .font(.caption2)
              .foregroundStyle(.primary)
          }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct CornerShape: Shape {
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = min(radius, min(rect.width, rect.height) / 2)
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: 0, y: rect.height - r))
    if r > 0 {
      path.addArc(
        center: CGPoint(x: r, y: rect.height - r),
        radius: r,
        startAngle: .degrees(180),
        endAngle: .degrees(90),
        clockwise: true
      )
    }
    path.addLine(to: CGPoint(x: rect.width, y: rect.height))
    return path
  }
}

#Preview {
  NavigationStack {
    CardPreferencesView()
  }
}
