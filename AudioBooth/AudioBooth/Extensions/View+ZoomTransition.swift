import SwiftUI

extension View {
  @ViewBuilder
  func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
    if #available(iOS 18.0, *) {
      self.matchedTransitionSource(id: id, in: namespace)
    } else {
      self
    }
  }

  @ViewBuilder
  func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
    if #available(iOS 18.0, *) {
      self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      self
    }
  }
}
