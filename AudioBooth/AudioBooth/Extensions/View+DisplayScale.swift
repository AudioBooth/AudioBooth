import SwiftUI

extension View {
  @ViewBuilder
  func displayScaled() -> some View {
    #if targetEnvironment(macCatalyst)
    modifier(DisplayScaleModifier())
    #else
    self
    #endif
  }
}

#if targetEnvironment(macCatalyst)
struct DisplayScaleModifier: ViewModifier {
  @ObservedObject private var preferences = UserPreferences.shared

  func body(content: Content) -> some View {
    let scale = preferences.displayScale
    GeometryReader { geometry in
      content
        .frame(
          width: geometry.size.width / scale,
          height: geometry.size.height / scale
        )
        .scaleEffect(scale)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
}
#endif
