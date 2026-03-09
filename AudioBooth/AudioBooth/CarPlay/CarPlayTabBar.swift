import API
@preconcurrency import CarPlay
import Combine
import Foundation

final class CarPlayTabBar: NSObject {
  private let interfaceController: CPInterfaceController
  private var tabs: [CPTemplate: CarPlayPageProtocol] = [:]
  private weak var nowPlaying: CarPlayNowPlaying?
  private var cancellables = Set<AnyCancellable>()

  private(set) var template: CPTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    self.template = Self.emptyTemplate

    super.init()

    interfaceController.delegate = self

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
      let home = CarPlayHome(interfaceController: interfaceController, nowPlaying: nowPlaying)
      let offline = CarPlayOffline(interfaceController: interfaceController, nowPlaying: nowPlaying)
      tabs = [home.template: home, offline.template: offline]
      newTemplate = CPTabBarTemplate(templates: [home.template, offline.template])
    } else {
      tabs = [:]
      newTemplate = Self.emptyTemplate
    }

    template = newTemplate
    interfaceController.setRootTemplate(newTemplate, animated: false, completion: nil)
  }
}

extension CarPlayTabBar: CPInterfaceControllerDelegate {
  func templateWillAppear(_ template: CPTemplate, animated: Bool) {
    tabs[template]?.willAppear()
  }
}
