import Combine
import SwiftUI

struct TimerCompletedAlertView: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 24) {
      HStack {
        Spacer()
        Button(
          action: { dismiss() },
          label: {
            Image(systemName: "xmark")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        )
        .buttonStyle(.plain)
      }
      .padding(.top, 24)

      Image(systemName: "timer")
        .font(.system(size: 60))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text("Time's up")
          .font(.title2)
          .bold()

        Text("Extend the timer or shake your phone to keep listening.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 8)

      VStack(spacing: 12) {
        Button(
          action: model.onExtendTapped,
          label: {
            Text(model.extendAction)
              .frame(maxWidth: .infinity)
          }
        )
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(
          action: model.onResetTapped,
          label: {
            Text("Reset timer")
              .frame(maxWidth: .infinity)
          }
        )
        .buttonStyle(.borderless)
        .controlSize(.large)
      }
      .padding(.bottom, 32)
    }
    .padding(.horizontal, 24)
    .presentationDetents([.height(360)])
    .presentationDragIndicator(.hidden)
  }
}

extension TimerCompletedAlertView {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt = Date()
    var extendAction: String

    var isExpired: Bool {
      Date().timeIntervalSince(createdAt) > 5 * 60
    }

    func onExtendTapped() {}
    func onResetTapped() {}

    init(extendAction: String) {
      self.extendAction = extendAction
    }
  }
}
