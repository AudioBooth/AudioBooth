import SwiftUI

struct PreferenceRow: View {
  let systemImage: String
  let tint: Color
  let title: Text
  let subtitle: Text?

  init(
    systemImage: String,
    tint: Color,
    title: String,
    subtitle: String? = nil
  ) {
    self.systemImage = systemImage
    self.tint = tint
    self.title = Text(title)
    self.subtitle = subtitle.map { Text($0) }
  }

  init(
    systemImage: String,
    tint: Color,
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil
  ) {
    self.systemImage = systemImage
    self.tint = tint
    self.title = Text(title)
    self.subtitle = subtitle.map { Text($0) }
  }

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 10)
        .fill(tint.opacity(0.15))
        .frame(width: 34, height: 34)
        .overlay(
          Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        title
          .font(.subheadline)
          .fontWeight(.medium)

        if let subtitle {
          subtitle
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
