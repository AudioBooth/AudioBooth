import SwiftUI

extension GeometryProxy {
  func sideOcclusionInsets(below top: CGFloat) -> EdgeInsets {
    #if !targetEnvironment(macCatalyst)
    if #available(iOS 27.1, *) {
      var insets = EdgeInsets()
      for region in reservedRegions(kind: .occlusion)
      where region.frame.maxY > top && region.frame.width < size.width / 2 {
        if region.frame.minX <= 0 {
          insets.leading = max(insets.leading, region.frame.maxX)
        } else if region.frame.maxX >= size.width {
          insets.trailing = max(insets.trailing, size.width - region.frame.minX)
        }
      }
      return insets
    }
    #endif

    return EdgeInsets()
  }

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
