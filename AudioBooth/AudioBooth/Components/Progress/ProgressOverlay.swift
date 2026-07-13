import Combine
import SwiftUI

public struct ProgressOverlay: View {
  let progress: Double?

  @ObservedObject private var preferences = UserPreferences.shared

  public var body: some View {
    ZStack(alignment: .topLeading) {
      if let progress, progress > 0 {
        Color.clear

        if progress > 0.99 {
          if preferences.dimCoverWhenCompleted {
            Color.black.opacity(0.4).padding(-10)
          }

          Image(systemName: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.6))
            .clipShape(.circle)
        } else {
          Text(progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(Color.white)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(.capsule)
        }
      }
    }
  }
}
