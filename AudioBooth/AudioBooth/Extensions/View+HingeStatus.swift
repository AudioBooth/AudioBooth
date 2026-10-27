import SwiftUI

extension EnvironmentValues {
  @Entry var isPartiallyFolded: Bool = false
}

extension View {
  func observesHinge() -> some View {
    modifier(HingeStatusModifier())
  }

  @ViewBuilder
  func onHingeStateChange(_ action: @escaping (_ hasHinge: Bool, _ isClosed: Bool) -> Void) -> some View {
    #if targetEnvironment(macCatalyst)
    self
    #else
    if #available(iOS 27.1, *) {
      onHingeChange { _, newContext in
        action(newContext.hinge != nil, newContext.hinge?.status == .closed)
      }
    } else {
      self
    }
    #endif
  }
}

private struct HingeStatusModifier: ViewModifier {
  @State private var isPartiallyFolded = false

  func body(content: Content) -> some View {
    #if targetEnvironment(macCatalyst)
    content
    #else
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
    #endif
  }
}
