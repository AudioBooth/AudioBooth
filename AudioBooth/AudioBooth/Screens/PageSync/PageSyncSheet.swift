import Combine
import SwiftUI
import UIKit

/// Scan a page of the printed book and jump to the same spot in the audiobook.
struct PageSyncSheet: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle("Page Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Close", systemImage: "xmark") {
              model.onDismiss()
              dismiss()
            }
            .tint(.primary)
          }
        }
    }
    .fullScreenCover(isPresented: $model.isScannerPresented) {
      PageScannerView(
        languages: model.scanLanguages,
        onScanned: model.onPageScanned,
        onCancelled: model.onScanCancelled
      )
    }
    .presentationDragIndicator(.visible)
    .onAppear(perform: model.onAppear)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .idle:
      idleView
    case .processing(let step):
      processingView(step)
    case .result(let result):
      resultView(result)
    case .failed(let message):
      failedView(message)
    }
  }

  private var idleView: some View {
    VStack(spacing: 24) {
      Spacer()

      Image(systemName: "camera.viewfinder")
        .font(.system(size: 64))
        .foregroundStyle(.tint)

      VStack(spacing: 8) {
        Text("Find your page in the audiobook")
          .font(.title2)
          .fontWeight(.semibold)
          .multilineTextAlignment(.center)

        Text(
          "Point the camera at the page you are reading in the printed book. AudioBooth reads it, finds it in the ebook and then listens to the audiobook to land on the exact spot."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      }

      Spacer()

      if model.isScannerSupported {
        Button(action: model.onScanTapped) {
          Label("Scan Page", systemImage: "camera.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      } else {
        Text("Scanning is not available on this device.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func processingView(_ step: String) -> some View {
    VStack(spacing: 16) {
      ProgressView()
        .controlSize(.large)

      Text(step)
        .font(.headline)
        .multilineTextAlignment(.center)

      Text("Usually under 20 seconds.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func resultView(_ result: Result) -> some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 12) {
        if let chapterTitle = result.chapterTitle {
          Text(chapterTitle)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }

        Text(formattedTime(result.time))
          .font(.system(size: 44, weight: .medium, design: .rounded))
          .monospacedDigit()

        HStack(spacing: 8) {
          switch result.precision {
          case .exact:
            Label("Exact match", systemImage: "checkmark.seal.fill")
              .foregroundStyle(.green)
          case .approximate:
            Label("Approximate", systemImage: "scope")
              .foregroundStyle(.orange)
          }

        }
        .font(.footnote)

        if result.isRefining {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(result.refiningStatus ?? String(localized: "Fine-tuning with the audio…"))
              .foregroundStyle(.secondary)
          }
          .font(.footnote)
        }
      }

      if result.needsDownload {
        VStack(spacing: 8) {
          Text("To pinpoint the exact spot, AudioBooth needs the audio on this device.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

          if result.isDownloading {
            Label("Downloading… scan again when it finishes", systemImage: "arrow.down.circle")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Button(action: model.onDownloadTapped) {
              Label("Download audiobook", systemImage: "arrow.down.circle")
                .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }

      if !result.excerpt.isEmpty {
        Text(verbatim: "“\(result.excerpt)”")
          .font(.callout)
          .italic()
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(4)
      }

      Spacer()

      VStack(spacing: 12) {
        Button(action: model.onPlayTapped) {
          Label("Play from here", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(action: model.onRetryTapped) {
          Label("Scan Again", systemImage: "camera.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
    }
  }

  private func failedView(_ message: String) -> some View {
    VStack(spacing: 24) {
      Spacer()

      Image(systemName: "exclamationmark.magnifyingglass")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text("Page not found")
          .font(.title3)
          .fontWeight(.semibold)

        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Spacer()

      Button(action: model.onRetryTapped) {
        Label("Try Again", systemImage: "camera.fill")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
  }

  private func formattedTime(_ time: TimeInterval) -> String {
    Duration.seconds(max(0, time)).formatted(.time(pattern: .hourMinuteSecond))
  }
}

extension PageSyncSheet {
  enum Precision {
    case approximate
    case exact
  }

  struct Result {
    var time: TimeInterval
    var chapterTitle: String?
    var excerpt: String
    var precision: Precision
    var isRefining: Bool
    var refiningStatus: String?
    /// The audio could not be fetched for an exact match; downloading the book would allow it.
    var needsDownload: Bool = false
    var isDownloading: Bool = false
  }

  enum Phase {
    case idle
    case processing(String)
    case result(Result)
    case failed(String)
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    let bookTitle: String

    var phase: Phase
    var isScannerPresented: Bool = false
    var isScannerSupported: Bool = true
    var scanLanguages: [String] = []
    var onFinished: (() -> Void)?

    init(bookTitle: String, phase: Phase = .idle) {
      self.bookTitle = bookTitle
      self.phase = phase
    }

    func onAppear() {}

    func onScanTapped() {
      isScannerPresented = true
    }

    func onPageScanned(_ lines: [String]) {}

    func onScanCancelled() {
      isScannerPresented = false
    }

    func onPlayTapped() {}

    func onDownloadTapped() {}

    func onRetryTapped() {
      phase = .idle
      isScannerPresented = true
    }

    func onDismiss() {}
  }
}

#Preview("Idle") {
  PageSyncSheet(model: PageSyncSheet.Model(bookTitle: "Sample Book"))
}

#Preview("Result") {
  PageSyncSheet(
    model: PageSyncSheet.Model(
      bookTitle: "Sample Book",
      phase: .result(
        PageSyncSheet.Result(
          time: 4_215,
          chapterTitle: "Chapter 7",
          excerpt: "It was the best of times, it was the worst of times, it was the age of wisdom",
          precision: .approximate,
          isRefining: true,
          refiningStatus: "Not there. Checking Chapter 8…"
        )
      )
    )
  )
}
