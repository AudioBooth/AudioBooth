import SwiftUI
import VisionKit

#if targetEnvironment(macCatalyst)
struct PageScannerView: View {
  var languages: [String]
  var onCaptured: (UIImage) -> Void
  var onCancelled: () -> Void

  static var isSupported: Bool { false }

  static func supportedLanguages(from candidates: [String]) -> [String] { [] }

  var body: some View {
    VStack(spacing: 16) {
      Text("Scanning isn't available on this device.")
      Button("Close", action: onCancelled)
    }
  }
}
#else
struct PageScannerView: View {
  var languages: [String]
  var onCaptured: (UIImage) -> Void
  var onCancelled: () -> Void

  @State private var scan = LiveScan()

  static var isSupported: Bool {
    DataScannerViewController.isSupported && DataScannerViewController.isAvailable
  }

  static func supportedLanguages(from candidates: [String]) -> [String] {
    let supported = DataScannerViewController.supportedTextRecognitionLanguages
    var result: [String] = []

    for candidate in candidates {
      let tag = candidate.replacingOccurrences(of: "_", with: "-")
      let base = tag.split(separator: "-").first.map { String($0) } ?? tag
      let match =
        supported.first { $0.caseInsensitiveCompare(tag) == .orderedSame }
        ?? supported.first { $0.lowercased().hasPrefix(base.lowercased() + "-") }
        ?? supported.first { $0.caseInsensitiveCompare(base) == .orderedSame }
      if let match, !result.contains(match) {
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

        status
          .padding(.bottom, 40)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: scan.captureNow)
    .preferredColorScheme(.dark)
    .onAppear { scan.start(onCaptured: onCaptured) }
    .onDisappear(perform: scan.stop)
  }

  private var status: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .stroke(Color.white.opacity(0.25), lineWidth: 4)
        Circle()
          .trim(from: 0, to: scan.progress)
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.linear(duration: 0.1), value: scan.progress)
        if scan.isCapturing {
          ProgressView()
            .controlSize(.small)
        }
      }
      .frame(width: 38, height: 38)

      Text(scan.hint)
        .font(.subheadline)
        .fontWeight(.medium)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: Capsule())
  }
}

extension PageScannerView {
  private static let wordsWorthCapturing = 40
  private static let secondsHoldingSteady: TimeInterval = 1.5
  private static let tick = Duration.milliseconds(100)
  private static let minimumFrameOverlap = 0.85

  @Observable
  final class LiveScan {
    private(set) var wordCount = 0
    private(set) var isCapturing = false
    private(set) var progress = 0.0

    weak var scanner: DataScannerViewController?

    private var steadySince: Date?
    private var ticker: Task<Void, Never>?
    private var onCaptured: ((UIImage) -> Void)?
    private var lastWords: Set<String> = []

    var hint: LocalizedStringKey {
      if isCapturing { return "Reading the page…" }
      if wordCount < PageScannerView.wordsWorthCapturing { return "Point at the page" }
      return "Hold still…"
    }

    func start(onCaptured: @escaping (UIImage) -> Void) {
      self.onCaptured = onCaptured
      guard ticker == nil else { return }

      ticker = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: PageScannerView.tick)
          self?.advance()
        }
      }
    }

    func stop() {
      ticker?.cancel()
      ticker = nil
    }

    func observe(words: [String]) {
      wordCount = words.count

      guard wordCount >= PageScannerView.wordsWorthCapturing else {
        steadySince = nil
        progress = 0
        lastWords = []
        return
      }

      let seen = Set(words)
      let overlap = Self.overlap(seen, lastWords)
      lastWords = seen

      guard overlap >= PageScannerView.minimumFrameOverlap else {
        steadySince = nil
        progress = 0
        return
      }
      if steadySince == nil {
        steadySince = Date()
      }
    }

    private static func overlap(_ words: Set<String>, _ previous: Set<String>) -> Double {
      guard !previous.isEmpty, !words.isEmpty else { return 0 }
      return Double(words.intersection(previous).count) / Double(max(words.count, previous.count))
    }

    func captureNow() {
      guard wordCount >= PageScannerView.wordsWorthCapturing else { return }
      capture()
    }

    private func advance() {
      guard !isCapturing, let steadySince else { return }

      let elapsed = Date().timeIntervalSince(steadySince)
      progress = min(1, elapsed / PageScannerView.secondsHoldingSteady)

      if elapsed >= PageScannerView.secondsHoldingSteady {
        capture()
      }
    }

    private func capture() {
      guard !isCapturing, let scanner else { return }

      isCapturing = true
      stop()
      lastWords = []

      Task { [weak self] in
        let image = try? await scanner.capturePhoto()
        guard let self else { return }

        if let image {
          onCaptured?(image)
        } else {
          isCapturing = false
          steadySince = nil
          progress = 0
          start(onCaptured: onCaptured ?? { _ in })
        }
      }
    }
  }
}

private struct LiveTextScanner: UIViewControllerRepresentable {
  let languages: [String]
  let scan: PageScannerView.LiveScan

  func makeCoordinator() -> Coordinator {
    Coordinator(scan: scan)
  }

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let controller = DataScannerViewController(
      recognizedDataTypes: [.text(languages: languages)],
      qualityLevel: .balanced,
      recognizesMultipleItems: true,
      isHighFrameRateTrackingEnabled: false,
      isHighlightingEnabled: false
    )
    controller.delegate = context.coordinator
    scan.scanner = controller
    return controller
  }

  func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
    guard !controller.isScanning else { return }
    try? controller.startScanning()
  }

  static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
    controller.stopScanning()
  }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    private let scan: PageScannerView.LiveScan

    init(scan: PageScannerView.LiveScan) {
      self.scan = scan
    }

    func dataScanner(
      _ scanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      report(allItems)
    }

    func dataScanner(
      _ scanner: DataScannerViewController,
      didUpdate updatedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      report(allItems)
    }

    func dataScanner(
      _ scanner: DataScannerViewController,
      didRemove removedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      report(allItems)
    }

    private func report(_ items: [RecognizedItem]) {
      let words = items.flatMap { item -> [String] in
        guard case .text(let text) = item else { return [] }
        return ReadAlongText.normalizedWords(in: text.transcript)
      }
      scan.observe(words: words)
    }
  }
}
#endif
