import UIKit

extension UIImage {
  var averageColor: UIColor? {
    guard let inputImage = CIImage(image: self) else { return nil }

    let extentVector = CIVector(
      x: inputImage.extent.origin.x,
      y: inputImage.extent.origin.y,
      z: inputImage.extent.size.width,
      w: inputImage.extent.size.height
    )

    guard
      let filter = CIFilter(
        name: "CIAreaAverage",
        parameters: [
          kCIInputImageKey: inputImage,
          kCIInputExtentKey: extentVector,
        ]
      ),
      let outputImage = filter.outputImage
    else { return nil }

    var bitmap = [UInt8](repeating: 0, count: 4)
    let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
    context.render(
      outputImage,
      toBitmap: &bitmap,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: nil
    )

    return UIColor(
      red: CGFloat(bitmap[0]) / 255,
      green: CGFloat(bitmap[1]) / 255,
      blue: CGFloat(bitmap[2]) / 255,
      alpha: CGFloat(bitmap[3]) / 255
    )
  }

  var vibrantColor: UIColor? {
    guard let ciImage = CIImage(image: self), !ciImage.extent.isEmpty else { return nil }

    let scale = 100 / max(ciImage.extent.width, ciImage.extent.height)
    let inputImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let count = 8

    guard
      let filter = CIFilter(
        name: "CIKMeans",
        parameters: [
          kCIInputImageKey: inputImage,
          kCIInputExtentKey: CIVector(cgRect: inputImage.extent),
          "inputCount": count,
          "inputPasses": 5,
          "inputPerceptual": true,
        ]
      ),
      let outputImage = filter.outputImage
    else { return nil }

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

    var bestColor: UIColor?
    var bestScore: CGFloat = 0

    for index in 0..<count {
      let offset = index * 4
      guard bitmap[offset + 3] >= 0.05 else { continue }

      let color = UIColor(
        red: CGFloat(min(max(bitmap[offset], 0), 1)),
        green: CGFloat(min(max(bitmap[offset + 1], 0), 1)),
        blue: CGFloat(min(max(bitmap[offset + 2], 0), 1)),
        alpha: 1
      )

      var saturation: CGFloat = 0
      var brightness: CGFloat = 0
      guard color.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil),
        saturation >= 0.25
      else { continue }

      let score = saturation * brightness
      if score > bestScore {
        bestScore = score
        bestColor = color
      }
    }

    return bestColor
  }
}
