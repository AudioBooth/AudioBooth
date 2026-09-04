import Combine
import Logging
import SwiftUI
import UIKit
import VisionKit

#if targetEnvironment(macCatalyst)
/// VisionKit's live scanner does not exist on Mac Catalyst.
struct PageScannerView: View {
  var languages: [String]
  var onScanned: ([String]) -> Void
  var onCancelled: () -> Void

  static var isSupported: Bool { false }

  static func supportedLanguages(from candidates: [String]) -> [String] { [] }

  var body: some View {
    VStack(spacing: 16) {
      Text("Scanning is not available on this device.")
      Button("Close", action: onCancelled)
    }
  }
}
#else
/// Live camera that reads the page as you point at it and captures on its own once it has
/// read enough words. No shutter, no cropping.
struct PageScannerView: View {
  var languages: [String]
  var onScanned: ([String]) -> Void
  var onCancelled: () -> Void

  @State private var scan = LiveScan()

  static var isSupported: Bool {
    DataScannerViewController.isSupported
  }

  static func supportedLanguages(from candidates: [String]) -> [String] {
    let supported = DataScannerViewController.supportedTextRecognitionLanguages
    var result: [String] = []
    for candidate in candidates {
      let base = candidate.split(separator: "-").first.map(String.init) ?? candidate
      if let match = supported.first(where: { $0 == candidate })
        ?? supported.first(where: { $0.lowercased().hasPrefix(base.lowercased()) }),
        !result.contains(match)
      {
        result.append(match)
      }
    }
    return result
  }

  var body: some View {
    ZStack {
      LiveTextScanner(languages: languages, scan: scan)
        .ignoresSafeArea()

      VStack {
        HStack {
          Spacer()
          Button(action: onCancelled) {
            Image(systemName: "xmark")
              .font(.headline)
              .padding(10)
              .background(.ultraThinMaterial, in: Circle())
          }
          .accessibilityLabel("Cancel")
        }
        .padding()

        Spacer()

        statusCard
          .padding(.horizontal, 24)
          .padding(.bottom, 32)
      }
    }
    .preferredColorScheme(.dark)
    .onChange(of: scan.captured?.count ?? 0) { _, count in
      if count > 0, let lines = scan.captured {
        onScanned(lines)
      }
    }
  }

  private var statusCard: some View {
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: 4)
          Circle()
            .trim(from: 0, to: scan.progress)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeOut(duration: 0.25), value: scan.progress)
          Text(verbatim: "\(scan.wordCount)")
            .font(.system(.footnote, design: .rounded))
            .monospacedDigit()
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 2) {
          Text(scan.hint)
            .font(.subheadline)
            .fontWeight(.semibold)
          Text("Fill the screen with the page. It captures on its own.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if scan.canCaptureManually {
        Button(action: scan.captureNow) {
          Label("Use what I see", systemImage: "text.viewfinder")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

extension PageScannerView {
  /// Words needed before the page is captured automatically.
  static let targetWords = 60
  static let minimumWordsForManualCapture = 20
  /// Consecutive stable readings required before capturing.
  private static let stableReadingsNeeded = 3

  @Observable
  final class LiveScan {
    private(set) var lines: [String] = []
    private(set) var wordCount: Int = 0
    private(set) var captured: [String]?
    private(set) var isUnavailable = false
    private var stableReadings = 0
    private var lastWordCount = 0
    private let startedAt = Date()

    var progress: Double {
      min(1, Double(wordCount) / Double(PageScannerView.targetWords))
    }

    var canCaptureManually: Bool {
      captured == nil && wordCount >= PageScannerView.minimumWordsForManualCapture
    }

    var hint: String {
      if isUnavailable {
        return String(localized: "The camera is not available")
      }
      if captured != nil {
        return String(localized: "Got it")
      }
      if wordCount == 0 {
        return Date().timeIntervalSince(startedAt) > 2
          ? String(localized: "Point the camera at the page")
          : String(localized: "Looking for text…")
      }
      if wordCount < PageScannerView.minimumWordsForManualCapture {
        return String(localized: "Move closer")
      }
      if wordCount < PageScannerView.targetWords {
        return String(localized: "Hold still…")
      }
      return String(localized: "Reading…")
    }

    func update(with items: [RecognizedItem]) {
      guard captured == nil else { return }

      let texts = items.compactMap { item -> (y: CGFloat, x: CGFloat, text: String)? in
        guard case .text(let text) = item else { return nil }
        let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }
        return (text.bounds.topLeft.y, text.bounds.topLeft.x, transcript)
      }
      // Items can be multi-line blocks; keep the reading order top to bottom.
      lines = texts.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        .flatMap { $0.text.components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      wordCount = lines.reduce(0) { $0 + $1.split(separator: " ").count }

      if wordCount >= PageScannerView.targetWords, abs(wordCount - lastWordCount) <= 3 {
        stableReadings += 1
      } else {
        stableReadings = 0
      }
      lastWordCount = wordCount

      if stableReadings >= PageScannerView.stableReadingsNeeded {
        captureNow()
      }
    }

    func captureNow() {
      guard captured == nil, !lines.isEmpty else { return }
      AppLogger.viewModel.info("Page Sync: live scan captured \(lines.count) lines, \(wordCount) words")
      captured = lines
    }

    func markUnavailable() {
      isUnavailable = true
    }
  }
}

/// UIKit wrapper around VisionKit's live text scanner.
private struct LiveTextScanner: UIViewControllerRepresentable {
  var languages: [String]
  var scan: PageScannerView.LiveScan

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.text(languages: languages)],
      qualityLevel: .accurate,
      recognizesMultipleItems: true,
      isHighFrameRateTrackingEnabled: false,
      isGuidanceEnabled: false,
      isHighlightingEnabled: false
    )
    scanner.delegate = context.coordinator
    return scanner
  }

  func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
    guard !scanner.isScanning, scan.captured == nil else { return }
    do {
      try scanner.startScanning()
    } catch {
      AppLogger.viewModel.error("Live scan could not start: \(error)")
      scan.markUnavailable()
    }
  }

  static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
    scanner.stopScanning()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(scan: scan)
  }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    private let scan: PageScannerView.LiveScan

    init(scan: PageScannerView.LiveScan) {
      self.scan = scan
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      scan.update(with: allItems)
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didUpdate updatedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      scan.update(with: allItems)
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didRemove removedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      scan.update(with: allItems)
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
      AppLogger.viewModel.error("Live scan unavailable: \(error)")
      scan.markUnavailable()
    }
  }
}
#endif
