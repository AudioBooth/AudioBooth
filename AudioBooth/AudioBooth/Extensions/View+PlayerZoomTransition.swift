import SwiftUI

private let playerZoomSourceID = "player"

extension View {
  @ViewBuilder
  func playerZoomSource(in namespace: Namespace.ID) -> some View {
    if #available(iOS 18.0, *) {
      self.matchedTransitionSource(id: playerZoomSourceID, in: namespace)
    } else {
      self
    }
  }

  @ViewBuilder
  func playerZoomTransition(in namespace: Namespace.ID) -> some View {
    if #available(iOS 18.0, *) {
      self.navigationTransition(.zoom(sourceID: playerZoomSourceID, in: namespace))
    } else {
      self
    }
  }
}
