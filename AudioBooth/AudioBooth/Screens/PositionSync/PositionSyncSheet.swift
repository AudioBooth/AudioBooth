import Combine
import SwiftUI

struct PositionSyncSheet: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle("Catch Up")
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
    .presentationDragIndicator(.visible)
    .onAppear(perform: model.onAppear)
    .onDisappear(perform: model.onDismiss)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .searching(let step):
      searching(step)
    case .result(let result):
      found(result)
    case .failed(let message):
      failed(message)
    }
  }

  private func searching(_ step: String) -> some View {
    VStack(spacing: 16) {
      NarrationWave()
        .padding(.bottom, 12)

      Text(step)
        .font(.headline)
        .multilineTextAlignment(.center)

      Text("Listening for the last words you read. This can take a minute.")
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

        Text(Duration.seconds(result.time).formatted(.time(pattern: .hourMinuteSecond)))
          .font(.system(size: 44, weight: .medium, design: .rounded))
          .monospacedDigit()

        if !result.isExact {
          Text("This is close, but not exact.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button(action: model.onSkipTapped) {
        Label("Skip to Here", systemImage: "forward.end.fill")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
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

      Button("Try Again", action: model.onRetryTapped)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
  }
}

extension PositionSyncSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    struct Result {
      var time: TimeInterval
      var chapterTitle: String?
      var isExact: Bool
    }

    enum Phase {
      case searching(String)
      case result(Result)
      case failed(String)
    }

    var phase: Phase

    var onFinished: (() -> Void)?

    func onAppear() {}
    func onSkipTapped() {}
    func onRetryTapped() {}
    func onCancelTapped() {}
    func onDismiss() {}

    init(phase: Phase = .searching("")) {
      self.phase = phase
    }
  }
}
