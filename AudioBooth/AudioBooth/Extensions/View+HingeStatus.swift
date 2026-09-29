import SwiftUI

extension EnvironmentValues {
  @Entry var isPartiallyFolded: Bool = false
}

extension View {
  func observesHinge() -> some View {
    modifier(HingeStatusModifier())
  }

}

private struct HingeStatusModifier: ViewModifier {
  @State private var isPartiallyFolded = false

  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      content
        .onHingeChange { _, newContext in
          let newValue = newContext.hinge?.status == .partiallyOpen
          guard newValue != isPartiallyFolded else { return }
          withAnimation {
            isPartiallyFolded = newValue
          }
        }
        .environment(\.isPartiallyFolded, isPartiallyFolded)
    } else {
      content
    }
  }
}
