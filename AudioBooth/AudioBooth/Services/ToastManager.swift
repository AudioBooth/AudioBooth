import Combine
import SwiftUI
import UIKit

public struct Toast {
  let message: String
  let type: ToastType

  enum ToastType {
    case error
    case success
    case info
  }

  private static var toasts = [UUID: Toast]()

  public init(error message: String) {
    self.message = message
    self.type = .error
  }

  public init(success message: String) {
    self.message = message
    self.type = .success
  }

  public init(message: String) {
    self.message = message
    self.type = .info
  }

  public func show() {
    for toast in Toast.toasts {
      toast.value.dismiss()
    }

    let id = UUID()
    Toast.toasts[id] = self

    Task { @MainActor in
      let window: UIWindow
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        window = PassThroughWindow(windowScene: windowScene)
      } else {
        window = PassThroughWindow()
      }
      window.backgroundColor = .clear
      window.windowLevel = .alert

      let model = ToastPage.Model()
      let rootView = ToastPage(toast: self, model: model)
      let rootViewController = UIHostingController(rootView: rootView)
      rootViewController.view.backgroundColor = .clear
      window.rootViewController = rootViewController
      window.isHidden = false

      let duration: TimeInterval =
        switch type {
        case .error: 5
        case .success: 3
        case .info: 2
        }
      try? await Task.sleep(for: .seconds(duration))
      model.visible = false
      try? await Task.sleep(for: .seconds(0.2))

      Toast.toasts[id] = nil
    }
  }

  func dismiss() {
    if let entry = Toast.toasts.first(where: { $0.value.message == message }) {
      Toast.toasts[entry.key] = nil
    }
  }

  private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      guard let rootView = rootViewController?.view else { return nil }
      return rootView.layer.hitTest(point)?.name == nil ? rootView : nil
    }
  }
}

struct ToastPage: View {
  let toast: Toast

  @ObservedObject var model: Model

  class Model: ObservableObject {
    @Published var visible: Bool = false
  }

  var body: some View {
    GeometryReader { geometry in
      VStack {
        if model.visible {
          ToastView(toast: toast, onDismiss: { model.visible = false })
            .padding(.top, max(geometry.safeAreaInsets.top, 50))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        Spacer()
      }
      .ignoresSafeArea()
      .animation(.spring(duration: 0.4), value: model.visible)
      .onAppear {
        DispatchQueue.main.async {
          model.visible = true
        }
      }
      .gesture(
        DragGesture(minimumDistance: 3.0, coordinateSpace: .local).onEnded { value in
          if -100...100 ~= value.translation.width, value.translation.height < 0 {
            model.visible = false
          }
        }
      )
    }
  }
}

struct ToastView: View {
  let toast: Toast
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

      Text(markdown)
        .font(.body)
        .foregroundColor(.primary)

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundColor(.secondary)
          .font(.caption)
          .contentShape(Rectangle())
      }
    }
    .padding()
    .glassEffect()
    .padding(.horizontal)
  }

  var markdown: AttributedString {
    do {
      return try AttributedString(markdown: toast.message)
    } catch {
      return AttributedString(stringLiteral: toast.message)
    }
  }

  @ViewBuilder
  private var legacyToast: some View {
    HStack {
      Image(systemName: iconName)
        .foregroundColor(iconColor)

      Text(markdown)
        .font(.body)
        .foregroundColor(.white)

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundColor(.white)
          .font(.caption)
      }
      .contentShape(Rectangle())
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
    case .info:
      return "info.circle.fill"
    }
  }

  private var iconColor: Color {
    if #available(iOS 26.0, *) {
      switch toast.type {
      case .error:
        return .red
      case .success:
        return .green
      case .info:
        return .blue
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
    case .info:
      return .blue
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    ToastView(toast: Toast(error: "Something went wrong!")) {}
    ToastView(toast: Toast(success: "Success!")) {}
  }
  .padding()
}
