import Foundation
import Logging
import UIKit
import Vision

nonisolated enum PagePhotoReader {
  enum ReaderError: LocalizedError {
    case unreadable

    var errorDescription: String? {
      switch self {
      case .unreadable:
        String(localized: "That photo couldn't be read. Try one taken closer, with the page flat.")
      }
    }
  }

  static func lines(in image: UIImage, languages: [String]) async throws -> [String] {
    guard let cgImage = image.cgImage else { throw ReaderError.unreadable }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    let recognized = recognitionLanguages(from: languages)

    let asked: String = languages.isEmpty ? "none" : languages.joined(separator: ", ")
    let using: String = recognized.isEmpty ? "the system default" : recognized.joined(separator: ", ")
    AppLogger.readAlong.info("Page Match: reading the page in \(using) (asked for \(asked))")

    let lines = try await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      if !recognized.isEmpty {
        request.recognitionLanguages = recognized
      }

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
      try handler.perform([request])

      return onMainPage(request.results ?? [])
        .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        .compactMap { $0.topCandidates(1).first?.string }
    }.value

    let preview: String = lines.prefix(3).joined(separator: " | ")
    AppLogger.readAlong.info(
      "Page Match: Vision read \(lines.count) line(s) from \(Int(image.size.width))x\(Int(image.size.height)), opening \"\(preview)\""
    )
    return lines
  }

  private static let minimumLinesToTrim = 8
  private static let minimumBlockOverlap = 0.5
  private static let minimumLinesKept = 0.5
  private static let maximumSingleCharacterShare = 0.6

  private static func onMainPage(
    _ observations: [VNRecognizedTextObservation]
  ) -> [VNRecognizedTextObservation] {
    let prose = observations.filter(isProse)
    let candidates = prose.count >= minimumLinesToTrim ? prose : observations
    guard candidates.count >= minimumLinesToTrim else { return observations }

    let widths = candidates.map { $0.boundingBox.width }.sorted()
    let body = candidates.filter { $0.boundingBox.width >= widths[widths.count / 2] }
    guard body.count >= 2 else { return candidates }

    let lower = median(body.map { $0.boundingBox.minX })
    let upper = median(body.map { $0.boundingBox.maxX })
    guard upper > lower else { return candidates }

    let kept = candidates.filter { observation in
      let box = observation.boundingBox
      let overlap = min(box.maxX, upper) - max(box.minX, lower)
      return overlap >= box.width * minimumBlockOverlap
    }

    guard Double(kept.count) >= Double(candidates.count) * minimumLinesKept else {
      return candidates
    }

    if kept.count < observations.count {
      AppLogger.readAlong.info(
        "Page Match: ignored \(observations.count - kept.count) line(s) outside the page"
      )
    }
    return kept
  }

  private static func isProse(_ observation: VNRecognizedTextObservation) -> Bool {
    guard let text = observation.topCandidates(1).first?.string else { return false }

    let tokens = text.split(whereSeparator: \.isWhitespace)
    guard !tokens.isEmpty else { return false }

    let single = tokens.filter { $0.count == 1 }.count
    return Double(single) / Double(tokens.count) <= maximumSingleCharacterShare
  }

  private static func median(_ values: [CGFloat]) -> CGFloat {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }

  private static func recognitionLanguages(from candidates: [String]) -> [String] {
    guard !candidates.isEmpty else { return [] }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    guard let supported = try? request.supportedRecognitionLanguages() else { return [] }

    return candidates.compactMap { candidate in
      supported.first { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        ?? supported.first { $0.caseInsensitiveCompare(base(of: candidate)) == .orderedSame }
        ?? supported.first { $0.lowercased().hasPrefix(base(of: candidate).lowercased() + "-") }
    }
    .reduce(into: [String]()) { result, language in
      guard !result.contains(language) else { return }
      result.append(language)
    }
  }

  private static func base(of tag: String) -> String {
    tag.split(separator: "-").first.map { String($0) } ?? tag
  }
}

nonisolated extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
