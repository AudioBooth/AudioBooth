import SwiftUI

struct ReadAlongStatusPill: View {
  let message: String
  let status: ReadAlongCoordinator.Status

  private var isFailure: Bool {
    if case .failed = status { return true }
    return false
  }

  var body: some View {
    HStack(spacing: 8) {
      icon
        .font(.footnote)
        .foregroundStyle(isFailure ? Color.red : Color.accentColor)

      Text(message)
        .font(.footnote)
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: .capsule)
    .overlay(Capsule().strokeBorder(.separator.opacity(0.5)))
    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    .padding(.horizontal, 24)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message)
  }

  @ViewBuilder
  private var icon: some View {
    switch status {
    case .preparing:
      ProgressView()
        .controlSize(.mini)
    case .locating:
      Image(systemName: "waveform.badge.magnifyingglass")
        .symbolEffect(.variableColor.iterative, options: .repeating)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
    case .off, .following:
      Image(systemName: "waveform")
    }
  }
}

#Preview {
  VStack(spacing: 16) {
    ReadAlongStatusPill(message: "Preparing Read Along… 45%", status: .preparing(0.45))
    ReadAlongStatusPill(message: "Listening for your place in the book…", status: .locating)
    ReadAlongStatusPill(message: "Read Along requires iOS 26 or later.", status: .failed(""))
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color(.systemBackground))
}
