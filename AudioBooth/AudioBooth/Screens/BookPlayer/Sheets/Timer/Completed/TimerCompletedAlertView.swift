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

      Image(systemName: model.style.icon)
        .font(.system(size: 60))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text(model.style.title)
          .font(.title2)
          .bold()

        Text(model.style.message)
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
            Text(model.style.resetAction)
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
  enum Style {
    case timer
    case alarm

    var icon: String {
      switch self {
      case .timer: "timer"
      case .alarm: "bell.fill"
      }
    }

    var title: LocalizedStringKey {
      switch self {
      case .timer: "Time's up"
      case .alarm: "Alarm"
      }
    }

    var message: LocalizedStringKey {
      switch self {
      case .timer: "Extend the timer or shake your phone to keep listening."
      case .alarm: "Snooze or stop the alarm."
      }
    }

    var resetAction: LocalizedStringKey {
      switch self {
      case .timer: "Reset timer"
      case .alarm: "Stop alarm"
      }
    }
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt = Date()
    var extendAction: String
    var style: Style

    var isExpired: Bool {
      Date().timeIntervalSince(createdAt) > 5 * 60
    }

    func onExtendTapped() {}
    func onResetTapped() {}

    init(extendAction: String, style: Style = .timer) {
      self.extendAction = extendAction
      self.style = style
    }
  }
}
