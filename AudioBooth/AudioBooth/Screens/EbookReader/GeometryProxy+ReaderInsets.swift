import SwiftUI

extension GeometryProxy {
  func topCornerInsets(at y: CGFloat) -> EdgeInsets {
    guard #available(iOS 27.1, *) else { return EdgeInsets() }

    let corners = containerCornerInsets
    return EdgeInsets(
      top: 0,
      leading: cornerClearance(corners.topLeading, at: y),
      bottom: 0,
      trailing: cornerClearance(corners.topTrailing, at: y)
    )
  }
}

private func cornerClearance(_ corner: CGSize, at y: CGFloat) -> CGFloat {
  guard corner.height > 0, y < corner.height else { return 0 }

  let depth = (corner.height - y) / corner.height
  return corner.width * (1 - (1 - depth * depth).squareRoot())
}
