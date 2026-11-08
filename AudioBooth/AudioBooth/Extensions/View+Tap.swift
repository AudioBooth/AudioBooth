import SwiftUI

extension View {
  func interactiveTarget() -> some View {
    #if targetEnvironment(macCatalyst)
    self
      .background(Color.black.opacity(0.001))
      .contentShape(.rect)
    #else
    self
      .contentShape(.rect)
    #endif
  }
}
