import SwiftUI

extension EnvironmentValues {
  @Entry var isPartiallyFolded: Bool = false
}

extension View {
  func observesHinge() -> some View {
    #if ENABLE_EXPERIMENTAL_HINGE_API
    modifier(HingeStatusModifier())
    #else
    self
    #endif
  }

  @ViewBuilder
  func onHingeStateChange(_ action: @escaping (_ hasHinge: Bool, _ isClosed: Bool) -> Void) -> some View {
    #if targetEnvironment(macCatalyst) || !ENABLE_EXPERIMENTAL_HINGE_API
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

#if ENABLE_EXPERIMENTAL_HINGE_API
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
#endif
