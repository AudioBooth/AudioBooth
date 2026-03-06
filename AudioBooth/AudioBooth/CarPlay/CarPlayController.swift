@preconcurrency import CarPlay
import Foundation

class CarPlayController: NSObject, CPInterfaceControllerDelegate {
  private let interfaceController: CPInterfaceController

  private let tabBar: CarPlayTabBar
  private let nowPlaying: CarPlayNowPlaying

  init(interfaceController: CPInterfaceController) async throws {
    self.interfaceController = interfaceController

    nowPlaying = .init(interfaceController: interfaceController)
    tabBar = .init(interfaceController: interfaceController, nowPlaying: nowPlaying)
    
    super.init()

    self.interfaceController.delegate = self
    
    try await interfaceController.setRootTemplate(tabBar.template, animated: false)
  }
  
  func templateWillAppear(_ template: CPTemplate, animated: Bool) {
    Task {
      await tabBar.handleWillAppear(for: template)
    }
  }
}
