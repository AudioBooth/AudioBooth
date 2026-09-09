import SwiftUI

struct PositionSyncBanner: View {
  let message: LocalizedStringResource
  let onCatchUp: () -> Void
  let onDismiss: (PositionSyncOffer.Dismissal) -> Void

  @State private var isChoosingScope = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "book.pages")
        .font(.footnote)
        .foregroundStyle(.tint)

      Text(message)
        .font(.footnote)
        .foregroundStyle(.primary)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button("Catch Up", action: onCatchUp)
        .font(.footnote.weight(.semibold))
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

      Button("Dismiss", systemImage: "xmark") { isChoosingScope = true }
        .labelStyle(.iconOnly)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: .rect(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.5)))
    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    .padding(.horizontal, 24)
    .confirmationDialog(
      "Hide this banner?",
      isPresented: $isChoosingScope,
      titleVisibility: .visible
    ) {
      Button("For Now") { onDismiss(.position) }
      Button("Until Next Session") { onDismiss(.session) }
      Button("Always for This Book") { onDismiss(.book) }
      Button("Cancel", role: .cancel) {}
    }
  }
}

#Preview {
  PositionSyncBanner(
    message: LocalizedStringResource(stringLiteral: "You've read 25 minutes further."),
    onCatchUp: {},
    onDismiss: { _ in }
  )
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color(.systemBackground))
}
