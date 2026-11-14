import Nuke
import UIKit

enum CarPlayCover {
  static func load(from url: URL) async -> UIImage? {
    let request = ImageRequest(
      url: url,
      processors: [ImageProcessors.Anonymous(id: "carplay-square-fit") { $0.squareFitted() }]
    )
    return try? await ImagePipeline.shared.image(for: request)
  }
}

extension UIImage {
  nonisolated fileprivate func squareFitted() -> UIImage {
    let side = max(size.width, size.height)
    guard side > 0, size.width != size.height else { return self }

    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    return renderer.image { _ in
      draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
    }
  }
}
