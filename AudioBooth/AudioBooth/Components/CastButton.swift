#if canImport(GoogleCast) && !os(watchOS)
import GoogleCast
import SwiftUI

struct CastButton: UIViewRepresentable {
  func makeUIView(context: Context) -> GCKUICastButton {
    let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    button.tintColor = UIColor.white
    return button
  }

  func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
#endif
