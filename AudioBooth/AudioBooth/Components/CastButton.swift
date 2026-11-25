#if !targetEnvironment(macCatalyst)
import GoogleCast
import SwiftUI

struct CastButton: UIViewRepresentable {
  func makeUIView(context: Context) -> GCKUICastButton {
    _ = CastManager.shared
    let button = GCKUICastButton(frame: .zero)
    button.tintColor = .white
    return button
  }

  func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
#endif
