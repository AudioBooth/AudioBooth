@preconcurrency import CarPlay
import Foundation

class CarPlayController {
  private let interfaceController: CPInterfaceController

  private let tabBar: CarPlayTabBar
  private let nowPlaying: CarPlayNowPlaying

  init(interfaceController: CPInterfaceController) async throws {
    self.interfaceController = interfaceController

    nowPlaying = .init(interfaceController: interfaceController)
    tabBar = .init(interfaceController: interfaceController, nowPlaying: nowPlaying)
    try await interfaceController.setRootTemplate(tabBar.template, animated: false)
  }
}
