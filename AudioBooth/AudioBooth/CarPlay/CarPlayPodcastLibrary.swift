import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayPodcastLibrary: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var selectedPodcast: CarPlayPodcastDetails?

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    let title = String(localized: "Podcasts")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "mic.fill")
    template.emptyViewTitleVariants = [String(localized: "Loading Podcasts...")]
  }

  func willAppear() {
    Task { await loadPodcasts() }
  }

  private func loadPodcasts() async {
    do {
      let page = try await Audiobookshelf.shared.podcasts.fetch()
      let podcasts = page.results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

      if podcasts.isEmpty {
        template.emptyViewTitleVariants = [String(localized: "No Podcasts")]
        template.emptyViewSubtitleVariants = [String(localized: "Your podcast library is empty")]
        template.updateSections([])
        return
      }

      let items = podcasts.map { podcast in
        createListItem(for: podcast)
      }

      let section = CPListSection(items: items)
      template.updateSections([section])
    } catch {
      template.emptyViewTitleVariants = [String(localized: "Failed to Load")]
      template.updateSections([])
    }
  }

  private func createListItem(for podcast: Podcast) -> CPListItem {
    let episodeCount = podcast.numEpisodes
    let item = CPListItem(
      text: podcast.title,
      detailText: "\(episodeCount) episode\(episodeCount == 1 ? "" : "s")"
    )

    if let coverURL = podcast.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.showPodcastDetails(podcast)
      completion()
    }

    return item
  }

  private func showPodcastDetails(_ podcast: Podcast) {
    guard let nowPlaying else { return }
    let details = CarPlayPodcastDetails(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      podcast: podcast
    )
    selectedPodcast = details
    interfaceController.pushTemplate(details.template, animated: true, completion: nil)
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}
