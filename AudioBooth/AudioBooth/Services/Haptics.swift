import UIKit

enum Haptics {
  static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    guard UserPreferences.shared.hapticsEnabled else { return }
    UIImpactFeedbackGenerator(style: style).impactOccurred()
  }

  static func selection() {
    guard UserPreferences.shared.hapticsEnabled else { return }
    UISelectionFeedbackGenerator().selectionChanged()
  }
}
