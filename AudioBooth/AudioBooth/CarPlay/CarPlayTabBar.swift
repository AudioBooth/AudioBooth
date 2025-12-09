import API
@preconcurrency import CarPlay
import Combine
import Foundation

final class CarPlayTabBar {
  private let interfaceController: CPInterfaceController
  private var home: CarPlayHome?
  private var offline: CarPlayOffline?
  private weak var nowPlaying: CarPlayNowPlaying?
  private var cancellables = Set<AnyCancellable>()

  private(set) var template: CPTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    self.template = Self.emptyTemplate

    Audiobookshelf.shared.libraries.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateTemplate()
      }
      .store(in: &cancellables)

    updateTemplate()
  }

  private static var emptyTemplate: CPListTemplate {
    let emptyTemplate = CPListTemplate(title: "AudioBooth", sections: [])
    emptyTemplate.emptyViewTitleVariants = ["Not Connected"]
    emptyTemplate.emptyViewSubtitleVariants = ["Connect to a server in the app"]
    return emptyTemplate
  }

  private func updateTemplate() {
    guard let nowPlaying else { return }

    let newTemplate: CPTemplate

    if Audiobookshelf.shared.authentication.server != nil, Audiobookshelf.shared.libraries.current != nil {
      let homeInstance = CarPlayHome(interfaceController: interfaceController, nowPlaying: nowPlaying)
      let offlineInstance = CarPlayOffline(interfaceController: interfaceController, nowPlaying: nowPlaying)
      home = homeInstance
      offline = offlineInstance
      newTemplate = CPTabBarTemplate(templates: [homeInstance.template, offlineInstance.template])
    } else {
      home = nil
      offline = nil
      newTemplate = Self.emptyTemplate
    }

    template = newTemplate
    interfaceController.setRootTemplate(newTemplate, animated: false, completion: nil)
  }
}
