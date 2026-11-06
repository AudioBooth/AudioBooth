import SwiftUI

extension EnvironmentValues {
  @Entry var isPartiallyFolded: Bool = false
}

extension View {
  func observesHinge() -> some View {
    self
  }

  func onHingeStateChange(_ action: @escaping (_ hasHinge: Bool, _ isClosed: Bool) -> Void) -> some View {
    self
  }
}
