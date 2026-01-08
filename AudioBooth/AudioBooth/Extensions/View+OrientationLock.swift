import SwiftUI
import UIKit

struct DeviceRotationViewModifier: ViewModifier {
  let orientation: UIInterfaceOrientationMask

  func body(content: Content) -> some View {
    content
      .onAppear {
        AppDelegate.orientationLock = orientation
      }
      .onDisappear {
        AppDelegate.orientationLock = .all
      }
  }
}

extension View {
  func orientationLock(_ orientation: UIInterfaceOrientationMask) -> some View {
    modifier(DeviceRotationViewModifier(orientation: orientation))
  }
}
