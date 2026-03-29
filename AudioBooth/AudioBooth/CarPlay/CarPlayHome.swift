import API
@preconcurrency import CarPlay
import Combine
import Foundation
import Nuke

final class CarPlayHome: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var currentPlayerCancellable: AnyCancellable?
  private var loadingCancellable: Task<Void, Never>?
  private var selected: CarPlayLibrary?
  private var selectedPodcast: CarPlayPodcastDetails?

  let template: CPListTemplate

  init(interfaceController: CPInterfaceController, nowPlaying: CarPlayNowPlaying) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying

    let title = String(localized: "Home")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "house.fill")

    currentPlayerCancellable = PlayerManager.shared.$current.sink { [weak self] _ in
      Task {
        guard let self, self.loadingCancellable == nil else { return }
        await self.loadSections()
      }
    }
  }

  func willAppear() {
    Task { await loadSections() }
  }

  private func loadSections() async {
    let sections = await buildSections()
    template.updateSections(sections)
  }

  private func buildSections() async -> [CPListSection] {
    var sections: [CPListSection] = []

    if let continueListeningSection = await buildContinueListeningSection() {
      sections.append(continueListeningSection)
    }

    let bookSections = await buildBookSections()
    sections.append(contentsOf: bookSections)

    let podcastSections = await buildPodcastSections()
    sections.append(contentsOf: podcastSections)

    let episodeSections = await buildEpisodeSections()
    sections.append(contentsOf: episodeSections)

    let seriesSections = await buildSeriesSections()
    sections.append(contentsOf: seriesSections)

    let authorSections = await buildAuthorSections()
    sections.append(contentsOf: authorSections)

    if sections.isEmpty {
      template.emptyViewTitleVariants = ["No Content"]
      template.emptyViewSubtitleVariants = ["Your library content will appear here"]
    }

    return sections
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }

  private func onEpisodeSelected(_ podcast: Podcast, completion: @escaping () -> Void) {
    guard let recentEpisode = podcast.recentEpisode else {
      completion()
      return
    }

    loadingCancellable = Task {
      do {
        let fullPodcast = try await Audiobookshelf.shared.podcasts.fetch(id: podcast.id)
        let episode = fullPodcast.media.episodes?.first(where: { $0.id == recentEpisode.id }) ?? recentEpisode

        PlayerManager.shared.setCurrent(
          episode: episode,
          podcastID: podcast.id,
          podcastTitle: podcast.title,
          podcastAuthor: podcast.author,
          coverURL: podcast.coverURL()
        )

        await waitForPlayerReady()
        try? await Task.sleep(for: .milliseconds(500))

        PlayerManager.shared.play()
        nowPlaying?.showNowPlaying()
      } catch {}

      completion()
      loadingCancellable = nil

      await loadSections()
    }
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

  private func onBookSelected(_ book: Book, completion: @escaping () -> Void) {
    loadingCancellable = Task {
      PlayerManager.shared.setCurrent(book)

      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))

      PlayerManager.shared.play()
      nowPlaying?.showNowPlaying()
      completion()
      loadingCancellable = nil

      await loadSections()
    }
  }

  private func waitForPlayerReady() async {
    guard PlayerManager.shared.current?.isLoading == true else { return }

    await withCheckedContinuation { continuation in
      observePlayerLoading(continuation: continuation)
    }
  }

  private func observePlayerLoading(continuation: CheckedContinuation<Void, Never>) {
    withObservationTracking {
      _ = PlayerManager.shared.current?.isLoading
    } onChange: { [weak self] in
      guard let self else {
        continuation.resume()
        return
      }

      RunLoop.main.perform {
        if PlayerManager.shared.current?.isLoading == false {
          continuation.resume()
        } else {
          self.observePlayerLoading(continuation: continuation)
        }
      }
    }
  }

  private func showLibrary(filterType: CarPlayLibrary.FilterType) {
    guard let nowPlaying else { return }
    let library = CarPlayLibrary(
      interfaceController: interfaceController,
      nowPlaying: nowPlaying,
      filterType: filterType
    )
    selected = library
    interfaceController.pushTemplate(library.template, animated: true, completion: nil)
  }
}

extension CarPlayHome {
  private func buildContinueListeningSection() async -> CPListSection? {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return nil
    }

    guard let continueListeningData = personalized.sections.first(where: { $0.id == "continue-listening" }) else {
      return nil
    }

    let header = String(localized: "Continue Listening")

    switch continueListeningData.entities {
    case .books(let books):
      let audioBooks = books.filter { $0.duration > 0 }
      guard !audioBooks.isEmpty else { return nil }
      let items = audioBooks.map { book in createListItem(for: book) }
      return CPListSection(items: items, header: header, sectionIndexTitle: nil)

    case .episodes(let podcasts):
      guard !podcasts.isEmpty else { return nil }
      let items = podcasts.map { podcast in createEpisodeListItem(for: podcast) }
      return CPListSection(items: items, header: header, sectionIndexTitle: nil)

    default:
      return nil
    }
  }

  private func buildBookSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard section.id != "continue-listening",
        case .books(let books) = section.entities,
        !books.isEmpty
      else {
        continue
      }

      let audioBooks = books.filter { $0.duration > 0 }
      guard !audioBooks.isEmpty else { continue }

      let items = audioBooks.map { book in
        createListItem(for: book)
      }

      let header =
        HomeSection(rawValue: section.id)?.displayName
        ?? section.label

      sections.append(CPListSection(items: items, header: header, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildSeriesSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard case .series(let seriesList) = section.entities, !seriesList.isEmpty else {
        continue
      }

      let items = seriesList.map { series in
        createListItem(for: series)
      }

      let header =
        HomeSection(rawValue: section.id)?.displayName
        ?? section.label

      sections.append(CPListSection(items: items, header: header, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildAuthorSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard case .authors(let authors) = section.entities, !authors.isEmpty else {
        continue
      }

      let items = authors.map { author in
        createListItem(for: author)
      }

      let header =
        HomeSection(rawValue: section.id)?.displayName
        ?? section.label

      sections.append(CPListSection(items: items, header: header, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildPodcastSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard section.id != "continue-listening",
        case .podcasts(let podcasts) = section.entities,
        !podcasts.isEmpty
      else {
        continue
      }

      let items = podcasts.map { podcast in
        createPodcastListItem(for: podcast)
      }

      let header =
        HomeSection(rawValue: section.id)?.displayName
        ?? section.label

      sections.append(CPListSection(items: items, header: header, sectionIndexTitle: nil))
    }

    return sections
  }

  private func buildEpisodeSections() async -> [CPListSection] {
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      return []
    }

    var sections: [CPListSection] = []

    for section in personalized.sections {
      guard section.id != "continue-listening",
        case .episodes(let podcasts) = section.entities,
        !podcasts.isEmpty
      else {
        continue
      }

      let items = podcasts.map { podcast in
        createEpisodeListItem(for: podcast)
      }

      let header =
        HomeSection(rawValue: section.id)?.displayName
        ?? section.label

      sections.append(CPListSection(items: items, header: header, sectionIndexTitle: nil))
    }

    return sections
  }

  private func createPodcastListItem(for podcast: Podcast) -> CPListItem {
    let item = CPListItem(
      text: podcast.title,
      detailText: podcast.author
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

  private func createEpisodeListItem(for podcast: Podcast) -> CPListItem {
    let item = CPListItem(
      text: podcast.recentEpisode?.title ?? podcast.title,
      detailText: podcast.title
    )

    item.isPlaying = (podcast.recentEpisode?.id ?? podcast.id) == PlayerManager.shared.current?.id

    if let coverURL = podcast.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onEpisodeSelected(podcast, completion: completion)
    }

    return item
  }

  private func createListItem(for book: Book) -> CPListItem {
    let item = CPListItem(
      text: book.title,
      detailText: book.authorName
    )

    item.isPlaying = book.id == PlayerManager.shared.current?.id

    if let coverURL = book.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onBookSelected(book, completion: completion)
    }

    return item
  }

  private func createListItem(for series: Series) -> CPListItem {
    let bookCount = series.books.count
    let item = CPListItem(
      text: series.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    if let firstBook = series.books.first, let coverURL = firstBook.coverURL() {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.showLibrary(filterType: .series(series))
      completion()
    }

    return item
  }

  private func createListItem(for author: Author) -> CPListItem {
    let bookCount = author.numBooks ?? 0
    let item = CPListItem(
      text: author.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    item.handler = { [weak self] _, completion in
      self?.showLibrary(filterType: .author(author))
      completion()
    }

    return item
  }
}
