import UIKit

extension UIImage {
  struct CoverPalette {
    let background: UIColor
    let accent: UIColor?
  }

  private struct ColorCluster {
    let hue: CGFloat
    let saturation: CGFloat
    let brightness: CGFloat
    let perceptualHue: CGFloat
    let weight: CGFloat

    var isColorful: Bool { saturation >= 0.2 && brightness >= 0.15 }

    func hueDistance(to other: ColorCluster) -> CGFloat {
      let distance = abs(perceptualHue - other.perceptualHue)
      return min(distance, 1 - distance) * 2
    }

    static func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func perceptualHue(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
      let r = linear(red)
      let g = linear(green)
      let b = linear(blue)

      let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
      let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
      let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

      let labA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
      let labB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

      let angle = atan2(labB, labA) / (2 * .pi)
      return angle < 0 ? angle + 1 : angle
    }
  }

  var coverPalette: CoverPalette? {
    guard let ciImage = CIImage(image: self), !ciImage.extent.isEmpty else { return nil }

    let clusters = Self.colorClusters(in: ciImage)
    guard let dominant = clusters.max(by: { $0.weight < $1.weight }) else { return nil }

    func contrast(_ cluster: ColorCluster) -> CGFloat {
      dominant.saturation < 0.1 ? 1 : cluster.hueDistance(to: dominant)
    }

    func vividness(_ cluster: ColorCluster) -> CGFloat {
      cluster.saturation * cluster.brightness * sqrt(cluster.weight)
    }

    let candidates = clusters.filter { $0.isColorful && $0.weight >= 0.01 }
    let contrastingAccent =
      candidates
      .filter { contrast($0) >= 0.17 }
      .max { vividness($0) * contrast($0) < vividness($1) * contrast($1) }
    let accentCluster = contrastingAccent ?? candidates.max { vividness($0) < vividness($1) }
    let isMonochrome = contrastingAccent == nil && accentCluster != nil

    let background = UIColor(
      hue: dominant.hue,
      saturation: min(dominant.saturation * 4, isMonochrome ? 0.25 : 0.7),
      brightness: min(dominant.brightness, 0.42),
      alpha: 1
    )

    let accent = accentCluster.map { cluster in
      var saturation = min(max(cluster.saturation, 0.5), 0.85)
      var brightness = max(cluster.brightness, 0.85)
      var color = UIColor(hue: cluster.hue, saturation: saturation, brightness: brightness, alpha: 1)

      while Self.contrastRatio(color, background) < 4.5 && saturation > 0.2 {
        saturation -= 0.05
        brightness = 1
        color = UIColor(hue: cluster.hue, saturation: saturation, brightness: brightness, alpha: 1)
      }

      return color
    }

    return CoverPalette(background: background, accent: accent)
  }

  private static func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
    func luminance(_ color: UIColor) -> CGFloat {
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      color.getRed(&red, green: &green, blue: &blue, alpha: nil)
      return 0.2126 * ColorCluster.linear(red) + 0.7152 * ColorCluster.linear(green) + 0.0722
        * ColorCluster.linear(blue)
    }

    let firstLuminance = luminance(first)
    let secondLuminance = luminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private static func colorClusters(in ciImage: CIImage) -> [ColorCluster] {
    let scale = 100 / max(ciImage.extent.width, ciImage.extent.height)
    let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let extent = scaledImage.extent
    let badgeWidth = extent.width * 0.45
    let badgeHeight = extent.height * 0.45
    let aboveBadge = scaledImage.cropped(
      to: CGRect(x: extent.minX, y: extent.minY + badgeHeight, width: extent.width, height: extent.height - badgeHeight)
    )
    let leftOfBadge = scaledImage.cropped(
      to: CGRect(x: extent.minX, y: extent.minY, width: extent.width - badgeWidth, height: badgeHeight)
    )
    let inputImage = aboveBadge.composited(over: leftOfBadge)
    let count = 8

    guard
      let filter = CIFilter(
        name: "CIKMeans",
        parameters: [
          kCIInputImageKey: inputImage,
          kCIInputExtentKey: CIVector(cgRect: extent),
          "inputCount": count,
          "inputPasses": 5,
          "inputPerceptual": true,
        ]
      ),
      let outputImage = filter.outputImage
    else { return [] }

    var bitmap = [Float](repeating: 0, count: count * 4)
    let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
    context.render(
      outputImage,
      toBitmap: &bitmap,
      rowBytes: count * 4 * MemoryLayout<Float>.size,
      bounds: CGRect(x: 0, y: 0, width: count, height: 1),
      format: .RGBAf,
      colorSpace: nil
    )

    let totalWeight = (0..<count).reduce(Float(0)) { $0 + bitmap[$1 * 4 + 3] }
    guard totalWeight > 0 else { return [] }

    return (0..<count).compactMap { index in
      let offset = index * 4
      let weight = CGFloat(bitmap[offset + 3] / totalWeight)
      guard weight > 0 else { return nil }

      let red = CGFloat(min(max(bitmap[offset], 0), 1))
      let green = CGFloat(min(max(bitmap[offset + 1], 0), 1))
      let blue = CGFloat(min(max(bitmap[offset + 2], 0), 1))
      let color = UIColor(red: red, green: green, blue: blue, alpha: 1)

      var hue: CGFloat = 0
      var saturation: CGFloat = 0
      var brightness: CGFloat = 0
      guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else {
        return nil
      }

      return ColorCluster(
        hue: hue,
        saturation: saturation,
        brightness: brightness,
        perceptualHue: ColorCluster.perceptualHue(red: red, green: green, blue: blue),
        weight: weight
      )
    }
  }
}
