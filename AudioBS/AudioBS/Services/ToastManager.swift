import SwiftUI

@Observable
@MainActor
final class ToastManager {
  static let shared = ToastManager()

  var currentToast: ToastMessage?

  private init() {}

  func show(error message: String) {
    currentToast = ToastMessage(message: message, type: .error)

    Task {
      try? await Task.sleep(for: .seconds(3))
      dismissToast()
    }
  }

  func show(success message: String) {
    currentToast = ToastMessage(message: message, type: .success)

    Task {
      try? await Task.sleep(for: .seconds(3))
      dismissToast()
    }
  }

  func dismissToast() {
    currentToast = nil
  }
}

struct ToastMessage {
  let message: String
  let type: ToastType

  enum ToastType {
    case error
    case success
  }
}

struct ToastView: View {
  let toast: ToastMessage
  let onDismiss: () -> Void

  var body: some View {
    if #available(iOS 26.0, *) {
      modernToast
    } else {
      legacyToast
    }
  }

  @available(iOS 26.0, *)
  @ViewBuilder
  private var modernToast: some View {
    HStack {
      Image(systemName: iconName)
        .foregroundColor(iconColor)

      Text(toast.message)
        .font(.body)
        .foregroundColor(.primary)

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundColor(.secondary)
          .font(.caption)
      }
    }
    .padding()
    .glassEffect()
    .padding(.horizontal)
  }

  @ViewBuilder
  private var legacyToast: some View {
    HStack {
      Image(systemName: iconName)
        .foregroundColor(iconColor)

      Text(toast.message)
        .font(.body)
        .foregroundColor(.white)

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundColor(.white)
          .font(.caption)
      }
    }
    .padding()
    .background(backgroundColor)
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    .padding(.horizontal)
  }

  private var iconName: String {
    switch toast.type {
    case .error:
      return "exclamationmark.triangle.fill"
    case .success:
      return "checkmark.circle.fill"
    }
  }

  private var iconColor: Color {
    if #available(iOS 26.0, *) {
      switch toast.type {
      case .error:
        return .red
      case .success:
        return .green
      }
    } else {
      return .white
    }
  }

  private var backgroundColor: Color {
    switch toast.type {
    case .error:
      return .red
    case .success:
      return .green
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    ToastView(toast: ToastMessage(message: "Something went wrong!", type: .error)) {}
    ToastView(toast: ToastMessage(message: "Success!", type: .success)) {}
  }
  .padding()
}
