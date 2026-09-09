import Combine
import PhotosUI
import SwiftUI
import UIKit

struct PageMatchSheet: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle("Page Match")
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
        onCaptured: model.onPageCaptured,
        onCancelled: model.onScanCancelled
      )
    }
    .photosPicker(isPresented: $model.isPhotoPickerPresented, selection: $model.photo, matching: .images)
    .onChange(of: model.photo) { _, _ in
      model.onPhotoPicked()
    }
    .presentationDragIndicator(.visible)
    .onAppear(perform: model.onAppear)
    .onDisappear(perform: model.onDismiss)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .idle:
      idle
    case .searching(let step):
      searching(step)
    case .result(let result):
      found(result)
    case .failed(let message):
      failed(message)
    }
  }

  private var idle: some View {
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

        Text(model.explanation)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Spacer()

      VStack(spacing: 12) {
        if model.canScan {
          Button(action: model.onScanTapped) {
            Label("Scan Page", systemImage: "camera.fill")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }

        if model.canChoosePhoto {
          Button(action: model.onChoosePhotoTapped) {
            Label("Choose a Photo", systemImage: "photo.on.rectangle")
          }
        }
      }
    }
  }

  private func searching(_ step: String) -> some View {
    VStack(spacing: 16) {
      NarrationWave()
        .padding(.bottom, 12)

      Text(step)
        .font(.headline)
        .multilineTextAlignment(.center)

      Text("Listening for the words you scanned. This can take a minute.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Button("Cancel", role: .destructive, action: model.onCancelTapped)
        .padding(.top, 8)
    }
  }

  private func found(_ result: Model.Result) -> some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 12) {
        if let chapterTitle = result.chapterTitle {
          Text(chapterTitle)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }

        Text(verbatim: result.formattedTime)
          .font(.system(size: 44, weight: .medium, design: .rounded))
          .monospacedDigit()

        if !result.isExact {
          Text("This is close, but not exact.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      VStack(spacing: 12) {
        Button(action: model.onPlayTapped) {
          Label("Play From Here", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button("Scan Again", action: model.onScanTapped)
      }
    }
  }

  private func failed(_ message: String) -> some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text(message)
        .multilineTextAlignment(.center)

      Spacer()

      VStack(spacing: 12) {
        if model.canScan {
          Button("Try Again", action: model.onScanTapped)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        if model.canChoosePhoto {
          Button(action: model.onChoosePhotoTapped) {
            Label("Choose a Photo", systemImage: "photo.on.rectangle")
          }
        }
      }
    }
  }
}

extension PageMatchSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    struct Result {
      var time: TimeInterval
      var chapterTitle: String?
      var isExact: Bool

      var formattedTime: String {
        let total = Int(time)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
          ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
          : String(format: "%d:%02d", minutes, seconds)
      }
    }

    enum Phase {
      case idle
      case searching(String)
      case result(Result)
      case failed(String)
    }

    var phase: Phase
    var explanation: String
    var canScan: Bool
    var canChoosePhoto: Bool = false
    var scanLanguages: [String]
    var isScannerPresented: Bool
    var isPhotoPickerPresented: Bool = false
    var photo: PhotosPickerItem?

    var onFinished: (() -> Void)?

    func onAppear() {}
    func onScanTapped() {}
    func onChoosePhotoTapped() {}
    func onPhotoPicked() {}
    func onScanCancelled() {}
    func onPageCaptured(_ image: UIImage) {}
    func onPlayTapped() {}
    func onCancelTapped() {}
    func onDismiss() {}

    init(
      phase: Phase = .idle,
      explanation: String = "",
      canScan: Bool = false,
      scanLanguages: [String] = [],
      isScannerPresented: Bool = false
    ) {
      self.phase = phase
      self.explanation = explanation
      self.canScan = canScan
      self.scanLanguages = scanLanguages
      self.isScannerPresented = isScannerPresented
    }
  }
}
