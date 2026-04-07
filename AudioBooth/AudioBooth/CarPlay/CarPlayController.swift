@preconcurrency import CarPlay
import Foundation

class CarPlayController {
  private let interfaceController: CPInterfaceController

  private let tabBar: CarPlayTabBar
  private let nowPlaying: CarPlayNowPlaying

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController

    nowPlaying = .init(interfaceController: interfaceController)
    tabBar = .init(interfaceController: interfaceController, nowPlaying: nowPlaying)

    tabBar.updateTemplate()
  }

  func showNowPlayingIfNeeded() {
    if UserPreferences.shared.openPlayerOnLaunch, PlayerManager.shared.current != nil {
      nowPlaying.showNowPlaying()
    }
  }
}
