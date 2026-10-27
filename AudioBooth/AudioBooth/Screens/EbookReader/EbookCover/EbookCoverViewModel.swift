import Combine
import ReadiumShared
import SwiftUI

final class EbookCoverViewModel: EbookCoverView.Model {
  private let preferences: EbookReaderPreferences
  private var isDismissed = false
  private var cancellables = Set<AnyCancellable>()

  init(preferences: EbookReaderPreferences) {
    self.preferences = preferences

    super.init()

    preferences.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateVisibility()
      }
      .store(in: &cancellables)
  }

  func load(_ publication: Publication) async {
    title = publication.metadata.title
    subtitle = publication.metadata.subtitle
    let authors = publication.metadata.authors.map(\.name)
    author = authors.isEmpty ? nil : authors.formatted(.list(type: .and))

    if case .success(let cover) = await publication.cover() {
      image = cover
    }
    isLoaded = true
  }

  override func onAppear() {
    revealsControlsOnAppear = false
  }

  override func onHingeChanged(hasHinge: Bool, isClosed: Bool) {
    self.hasHinge = hasHinge
    isHingeClosed = isClosed
    if !isClosed { isDismissed = false }
    updateVisibility()
  }

  override func onReadTapped() {
    isDismissed = true
    updateVisibility()
  }

  private func updateVisibility() {
    isVisible = isHingeClosed && !isDismissed && preferences.showCoverWhenClosed
  }
}
