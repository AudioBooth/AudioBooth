import API
@preconcurrency import CarPlay
import Combine
import Foundation

final class CarPlayTabBar: NSObject {
  private let interfaceController: CPInterfaceController
  private var tabs: [CPTemplate: CarPlayPageProtocol] = [:]
  private weak var nowPlaying: CarPlayNowPlaying?
  private var cancellables = Set<AnyCancellable>()
  private var signature: String?
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
  }

  private static var emptyTemplate: CPListTemplate {
    let emptyTemplate = CPListTemplate(title: "AudioBooth", sections: [])
    emptyTemplate.emptyViewTitleVariants = ["Not Connected"]
    emptyTemplate.emptyViewSubtitleVariants = ["Connect to a server in the app"]
    return emptyTemplate
  }

  func updateTemplate(completion: (() -> Void)? = nil) {
    guard let nowPlaying else { return }

    let libraries = Audiobookshelf.shared.libraries
    let newSignature = [
      Audiobookshelf.shared.authentication.server?.id,
      libraries.current?.id,
      libraries.current?.mediaType.rawValue,
      libraries.libraries.map(\.id).joined(separator: ","),
    ]
    .map { $0 ?? "" }
    .joined(separator: "|")

    guard newSignature != signature else { return }

    let newTemplate: CPTemplate

    if Audiobookshelf.shared.authentication.server != nil, let library = Audiobookshelf.shared.libraries.current {
      let home = CarPlayHome(interfaceController: interfaceController, nowPlaying: nowPlaying)
      let offline = CarPlayOffline(interfaceController: interfaceController, nowPlaying: nowPlaying)

      var templates: [CPTemplate] = [home.template]
      tabs = [home.template: home, offline.template: offline]

      if library.mediaType == .podcast {
        let podcastLibrary = CarPlayPodcastLibrary(interfaceController: interfaceController, nowPlaying: nowPlaying)
        tabs[podcastLibrary.template] = podcastLibrary
        templates.append(podcastLibrary.template)
      } else {
        let collections = CarPlayCollections(interfaceController: interfaceController, nowPlaying: nowPlaying)
        tabs[collections.template] = collections
        templates.append(collections.template)
      }

      templates.append(offline.template)

      if Audiobookshelf.shared.libraries.libraries.count > 1 {
        let librarySelector = CarPlayLibrarySelector()
        tabs[librarySelector.template] = librarySelector
        templates.append(librarySelector.template)
      }

      newTemplate = CPTabBarTemplate(templates: templates)
    } else {
      tabs = [:]
      newTemplate = Self.emptyTemplate
    }

    template = newTemplate
    signature = newSignature
    interfaceController.setRootTemplate(newTemplate, animated: false) { _, _ in
      completion?()
    }
  }
}

extension CarPlayTabBar: CPInterfaceControllerDelegate {
  func templateWillAppear(_ template: CPTemplate, animated: Bool) {
    tabs[template]?.willAppear()
  }
}
