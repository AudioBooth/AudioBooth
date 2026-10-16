import Foundation
import ImageIO
import UIKit

/// Loads cover art for widgets within the 30 MB widget extension memory limit.
///
/// Images are decoded straight to the requested size with ImageIO instead of going
/// through an image pipeline, so a refresh never holds a full-size bitmap, cache or
/// intermediate copy. Exceeding the limit gets the extension killed before the
/// timeline is delivered, and the widget then keeps showing its last rendered entry.
enum CoverImageLoader {
  static func image(from url: URL, maxPixelSize: Int) async -> UIImage? {
    var requestURL = url
    if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.query = "width=\(maxPixelSize)"
      requestURL = components.url ?? url
    }

    let request = URLRequest(url: requestURL, timeoutInterval: 10)
    guard let (data, _) = try? await URLSession.shared.data(for: request) else {
      return nil
    }

    return downsample(data, maxPixelSize: maxPixelSize)
  }

  private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
      return nil
    }

    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }

    return UIImage(cgImage: image)
  }
}
