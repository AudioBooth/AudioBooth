@preconcurrency import CarPlay
import Foundation

class CarPlayController {
  private let tabBar: CarPlayTabBar
  private let nowPlaying: CarPlayNowPlaying

  init(interfaceController: CPInterfaceController) {
    nowPlaying = .init(interfaceController: interfaceController)
    tabBar = .init(interfaceController: interfaceController, nowPlaying: nowPlaying)

    tabBar.updateTemplate { [weak self] in
      self?.showNowPlayingIfNeeded()
    }
  }

  func showNowPlayingIfNeeded() {
    if UserPreferences.shared.openPlayerOnLaunch, PlayerManager.shared.current != nil {
      nowPlaying.showNowPlaying()
    }
  }
}
