import API
@preconcurrency import CarPlay
import Combine
import Foundation
import Models
import Nuke

final class CarPlayHome: CarPlayPageProtocol {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private var currentPlayerCancellable: AnyCancellable?
  private var loadingCancellable: Task<Void, Never>?
  private var selected: CarPlayLibrary?
  private var selectedPodcast: CarPlayPodcastDetails?
  private var selectedSectionTemplate: CPListTemplate?

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
    guard let personalized = Audiobookshelf.shared.libraries.getCachedPersonalized() else {
      template.emptyViewTitleVariants = ["No Content"]
      template.emptyViewSubtitleVariants = ["Your library content will appear here"]
      return []
    }

    var sections: [CPListSection] = []

    for personalizedSection in personalized.sections {
      let header = HomeSection(rawValue: personalizedSection.id)?.displayName ?? personalizedSection.label

      switch personalizedSection.entities {
      case .books(let books):
        let filtered = books.filter { $0.duration > 0 }
        guard !filtered.isEmpty else { continue }
        let isContinueListening = personalizedSection.id == "continue-listening"
        if let built = await buildImageRowSection(
          header: header,
          items: filtered,
          isContinueListening: isContinueListening
        ) {
          sections.append(built)
        }

      case .podcasts(let podcasts):
        guard !podcasts.isEmpty else { continue }
        if let built = await buildImageRowSection(header: header, items: podcasts) {
          sections.append(built)
        }

      case .episodes(let podcasts):
        guard !podcasts.isEmpty else { continue }
        let isContinueListening = personalizedSection.id == "continue-listening"
        if let built = await buildImageRowSection(
          header: header,
          items: podcasts,
          isEpisode: true,
          isContinueListening: isContinueListening
        ) {
          sections.append(built)
        }

      case .series(let seriesList):
        guard !seriesList.isEmpty else { continue }
        if let built = await buildImageRowSection(header: header, items: seriesList as [API.Series]) {
          sections.append(built)
        }

      case .authors(let authors):
        guard !authors.isEmpty else { continue }
        if let built = await buildImageRowSection(header: header, items: authors as [API.Author]) {
          sections.append(built)
        }

      default:
        continue
      }
    }

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

  private func showSectionList(title: String, items: [CPListItem]) {
    let template = CPListTemplate(title: title, sections: [CPListSection(items: items)])
    selectedSectionTemplate = template
    interfaceController.pushTemplate(template, animated: true, completion: nil)
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
  private func buildImageRowSection(
    header: String,
    items: [Book],
    isContinueListening: Bool = false
  ) async -> CPListSection? {
    if #available(iOS 26.0, *) {
      let images = await loadImages(items.map { $0.coverURL() })
      let elements = zip(items, images).map { book, image in
        var subtitle = book.authorName
        if isContinueListening, let progress = try? MediaProgress.fetch(bookID: book.id) {
          subtitle = progress.remaining.formattedTimeLeft
        }
        return CPListImageRowItemRowElement(
          image: image ?? UIImage(),
          title: book.title,
          subtitle: subtitle
        )
      }
      let rowItem = CPListImageRowItem(text: header, elements: elements, allowsMultipleLines: false)
      rowItem.listImageRowHandler = {
        [weak self] (_: CPListImageRowItem, index: Int, completion: @escaping () -> Void) in
        self?.onBookSelected(items[index], completion: completion)
      }
      rowItem.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
        let listItems = items.map { book in self?.createListItem(for: book) }.compactMap { $0 }
        self?.showSectionList(title: header, items: listItems)
        completion()
      }
      return CPListSection(items: [rowItem])
    } else {
      let listItems = items.map { book in createListItem(for: book) }
      return CPListSection(items: listItems, header: header, sectionIndexTitle: nil)
    }
  }

  private func buildImageRowSection(
    header: String,
    items: [Podcast],
    isEpisode: Bool = false,
    isContinueListening: Bool = false
  ) async -> CPListSection? {
    if #available(iOS 26.0, *) {
      let images = await loadImages(items.map { $0.coverURL() })
      let elements = zip(items, images).map { podcast, image in
        var title = isEpisode ? (podcast.recentEpisode?.title ?? podcast.title) : podcast.title
        var subtitle = isEpisode ? podcast.title : podcast.author
        if isContinueListening, let episodeID = podcast.recentEpisode?.id,
          let progress = try? MediaProgress.fetch(bookID: episodeID)
        {
          title = podcast.recentEpisode?.title ?? podcast.title
          subtitle = progress.remaining.formattedTimeLeft
        }
        return CPListImageRowItemRowElement(
          image: image ?? UIImage(),
          title: title,
          subtitle: subtitle
        )
      }
      let rowItem = CPListImageRowItem(text: header, elements: elements, allowsMultipleLines: false)
      rowItem.listImageRowHandler = {
        [weak self] (_: CPListImageRowItem, index: Int, completion: @escaping () -> Void) in
        let podcast = items[index]
        if isEpisode {
          self?.onEpisodeSelected(podcast, completion: completion)
        } else {
          self?.showPodcastDetails(podcast)
          completion()
        }
      }
      rowItem.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
        if isEpisode {
          let listItems = items.map { podcast in self?.createEpisodeListItem(for: podcast) }.compactMap { $0 }
          self?.showSectionList(title: header, items: listItems)
        } else {
          let listItems = items.map { podcast in self?.createPodcastListItem(for: podcast) }.compactMap { $0 }
          self?.showSectionList(title: header, items: listItems)
        }
        completion()
      }
      return CPListSection(items: [rowItem])
    } else {
      if isEpisode {
        let listItems = items.map { podcast in createEpisodeListItem(for: podcast) }
        return CPListSection(items: listItems, header: header, sectionIndexTitle: nil)
      } else {
        let listItems = items.map { podcast in createPodcastListItem(for: podcast) }
        return CPListSection(items: listItems, header: header, sectionIndexTitle: nil)
      }
    }
  }

  private func buildImageRowSection(header: String, items: [API.Series]) async -> CPListSection? {
    if #available(iOS 26.0, *) {
      let images = await loadImages(items.map { $0.books.first?.coverURL() })
      let elements = zip(items, images).map { series, image in
        let bookCount = series.books.count
        return CPListImageRowItemRowElement(
          image: image ?? UIImage(),
          title: series.name,
          subtitle: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
        )
      }
      let rowItem = CPListImageRowItem(text: header, elements: elements, allowsMultipleLines: false)
      rowItem.listImageRowHandler = {
        [weak self] (_: CPListImageRowItem, index: Int, completion: @escaping () -> Void) in
        self?.showLibrary(filterType: .series(items[index]))
        completion()
      }
      rowItem.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
        let listItems = items.map { series in self?.createListItem(for: series) }.compactMap { $0 }
        self?.showSectionList(title: header, items: listItems)
        completion()
      }
      return CPListSection(items: [rowItem])
    } else {
      let listItems = items.map { series in createListItem(for: series) }
      return CPListSection(items: listItems, header: header, sectionIndexTitle: nil)
    }
  }

  private func buildImageRowSection(header: String, items: [API.Author]) async -> CPListSection? {
    if #available(iOS 26.0, *) {
      let elements = items.map { author in
        let bookCount = author.numBooks ?? 0
        return CPListImageRowItemRowElement(
          image: UIImage(),
          title: author.name,
          subtitle: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
        )
      }
      let rowItem = CPListImageRowItem(text: header, elements: elements, allowsMultipleLines: false)
      rowItem.listImageRowHandler = {
        [weak self] (_: CPListImageRowItem, index: Int, completion: @escaping () -> Void) in
        self?.showLibrary(filterType: .author(items[index]))
        completion()
      }
      rowItem.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
        let listItems = items.map { author in self?.createListItem(for: author) }.compactMap { $0 }
        self?.showSectionList(title: header, items: listItems)
        completion()
      }
      return CPListSection(items: [rowItem])
    } else {
      let listItems = items.map { author in createListItem(for: author) }
      return CPListSection(items: listItems, header: header, sectionIndexTitle: nil)
    }
  }

  private func loadImages(_ urls: [URL?]) async -> [UIImage?] {
    await withTaskGroup(of: (Int, UIImage?).self) { group in
      for (index, url) in urls.enumerated() {
        group.addTask {
          guard let url else { return (index, nil) }
          return (index, await self.loadImage(from: url))
        }
      }
      var results = [UIImage?](repeating: nil, count: urls.count)
      for await (index, image) in group {
        results[index] = image
      }
      return results
    }
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

  private func createListItem(for series: API.Series) -> CPListItem {
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

    item.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
      self?.showLibrary(filterType: .series(series))
      completion()
    }

    return item
  }

  private func createListItem(for author: API.Author) -> CPListItem {
    let bookCount = author.numBooks ?? 0
    let item = CPListItem(
      text: author.name,
      detailText: "\(bookCount) book\(bookCount == 1 ? "" : "s")"
    )

    item.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
      self?.showLibrary(filterType: .author(author))
      completion()
    }

    return item
  }
}
