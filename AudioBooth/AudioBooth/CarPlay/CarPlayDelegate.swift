@preconcurrency import CarPlay
import Foundation
import OSLog

public final class CarPlayDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private var controller: CarPlayController?

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    updateController()
  }

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    controller = nil
  }
}

private extension CarPlayDelegate {
  func updateController() {
    Task {
      guard let interfaceController else { return }

      if controller == nil {
        controller = try await CarPlayController(interfaceController: interfaceController)
      }
    }
  }
}
