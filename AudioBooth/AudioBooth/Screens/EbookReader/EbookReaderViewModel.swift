import API
import Combine
import Foundation
import Logging
import Models
import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit

final class EbookReaderViewModel: EbookReaderView.Model {
  enum Source {
    case local(URL)
    case remote(URL)
  }

  private let source: Source
  private let bookID: String?
  private var publication: Publication?
  private var httpServer: HTTPServer?
  private var navigator: (any Navigator)?
  private var lastProgressUpdate: Date?
  private let audiobookshelf = Audiobookshelf.shared
  private var temporaryFileURL: URL?

  private var cancellables = Set<AnyCancellable>()

  private lazy var assetRetriever = AssetRetriever(
    httpClient: DefaultHTTPClient()
  )

  private lazy var publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
      httpClient: DefaultHTTPClient(),
      assetRetriever: assetRetriever,
      pdfFactory: DefaultPDFDocumentFactory()
    )
  )

  init(source: Source, bookID: String?) {
    self.source = source
    self.bookID = bookID
    super.init()
    observeChanges()
  }

  func observeChanges() {
    preferences.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.applyPreferences(self.preferences)
      }
      .store(in: &cancellables)
  }

  override func onAppear() {
    Task {
      await loadEbook()
    }
  }

  override func onDisappear() {
    cleanupTemporaryFile()
  }

  private func loadEbook() async {
    do {
      isLoading = true
      error = nil

      let localURL: URL
      switch source {
      case .local(let url):
        localURL = url

      case .remote(let remoteURL):
        if let bookID {
          localURL = try await downloadEbook(bookID: bookID, remoteURL: remoteURL)
        } else {
          localURL = try await downloadTemporaryFile(from: remoteURL)
          temporaryFileURL = localURL
        }
      }

      guard let fileURL = FileURL(url: localURL) else { throw EbookError.unsupportedURL }

      let asset = try await assetRetriever.retrieve(url: fileURL).get()

      let publication = try await publicationOpener.open(
        asset: asset,
        allowUserInteraction: false
      ).get()

      self.publication = publication
      self.supportsSettings = publication.conforms(to: .epub)
      self.supportsSearch = publication.isSearchable

      let httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
      self.httpServer = httpServer

      let initialLocation: Locator?
      if let bookID {
        let mediaProgress = try? MediaProgress.fetch(bookID: bookID)

        if let locationString = mediaProgress?.ebookLocation,
          let locator = try? Locator(jsonString: locationString)
        {
          initialLocation = locator
          AppLogger.viewModel.info("Restored from ebookLocation")
        } else {
          let progress = MediaProgress.progress(for: bookID)
          initialLocation = await publication.locate(progression: progress)
          AppLogger.viewModel.info("Restored from ebookProgress: \(progress)")
        }
      } else {
        initialLocation = nil
      }

      let navigator = try createNavigator(
        for: publication,
        httpServer: httpServer,
        initialLocation: initialLocation
      )
      self.navigator = navigator
      self.readerViewController = navigator as? UIViewController

      updateProgress()
      updateCurrentChapterIndex()

      await setupChapters()

      isLoading = false
    } catch {
      AppLogger.viewModel.error("Failed to load ebook: \(error)")
      self.error = "Failed to load ebook. Please try again."
      isLoading = false
    }
  }

  private func createNavigator(
    for publication: Publication,
    httpServer: HTTPServer,
    initialLocation: Locator?
  ) throws -> any Navigator {
    if publication.conforms(to: .epub) {
      let navigator = try EPUBNavigatorViewController(
        publication: publication,
        initialLocation: initialLocation,
        config: EPUBNavigatorViewController.Configuration(
          preferences: preferences.toEPUBPreferences(),
          contentInset: [
            .compact: (top: 0, bottom: 0),
            .regular: (top: 0, bottom: 0),
          ]
        ),
        httpServer: httpServer
      )
      navigator.delegate = self
      return navigator
    } else if publication.conforms(to: .pdf) {
      let navigator = try PDFNavigatorViewController(
        publication: publication,
        initialLocation: initialLocation,
        config: .init(),
        httpServer: httpServer
      )
      navigator.delegate = self
      return navigator
    } else if publication.conforms(to: .divina) {
      let navigator = try CBZNavigatorViewController(
        publication: publication,
        initialLocation: initialLocation,
        httpServer: httpServer
      )
      navigator.delegate = self
      return navigator
    } else {
      throw EbookError.unsupportedFormat
    }
  }

  private func updateProgress() {
    guard let navigator = navigator else { return }
    if let progression = navigator.currentLocation?.locations.totalProgression {
      progress = progression
    }
  }

  private func setupChapters() async {
    guard let publication = publication else { return }

    if let toc = try? await publication.tableOfContents().get(), !toc.isEmpty {
      let chapterItems = toc.map { link in
        EbookChapterPickerSheet.Model.Chapter(
          id: link.url().path,
          title: link.title ?? "Untitled",
          link: link
        )
      }

      let chaptersModel = EbookChapterPickerViewModel(chapters: chapterItems)
      chaptersModel.onChapterSelected = { [weak self] chapter in
        self?.navigateToChapter(chapter)
      }

      self.chapters = chaptersModel
      updateCurrentChapterIndex()
    }
  }

  private func updateCurrentChapterIndex() {
    guard let chapters, let navigator else { return }

    if let current = navigator.currentLocation?.href {
      let index = chapters.chapters.firstIndex(where: { $0.id == current.string }) ?? 0
      chapters.currentIndex = index
      AppLogger.viewModel.info("Current chapter index: \(index)")
    }
  }

  private func navigateToChapter(_ chapter: EbookChapterPickerSheet.Model.Chapter) {
    guard let navigator else {
      AppLogger.viewModel.error("Navigator or publication not available")
      return
    }

    Task {
      AppLogger.viewModel.info("Navigating to chapter: \(chapter.title) - \(chapter.link.href)")
      await navigator.go(to: chapter.link)
    }
  }

  override func onTableOfContentsTapped() {
    chapters?.isPresented = true
  }

  override func onSettingsTapped() {
    AppLogger.viewModel.info("Settings tapped")
  }

  override func onProgressTapped() {
    AppLogger.viewModel.info("Progress tapped - current: \(Int(progress * 100))%")
  }

  override func onSearchTapped() {
    guard let publication else { return }

    let searchViewModel = EbookSearchViewModel(publication: publication)

    searchViewModel.onResultSelected = { [weak self] locator, index in
      self?.navigateToSearchResult(locator: locator)
      self?.highlightSearchResult(locator: locator)
      self?.search = nil
    }

    searchViewModel.onDismissed = { [weak self] in
      self?.clearSearchHighlights()
      self?.search = nil
    }

    search = searchViewModel
  }

  override func onPreferencesChanged(_ preferences: EbookReaderPreferences) {
    AppLogger.viewModel.info("Applying preferences")
    applyPreferences(preferences)
  }

  override func onTapLeft() {
    Task {
      await navigator?.goBackward()
    }
  }

  override func onTapRight() {
    Task {
      await navigator?.goForward()
    }
  }

  private func applyPreferences(_ preferences: EbookReaderPreferences) {
    guard let epubNavigator = navigator as? EPUBNavigatorViewController else {
      AppLogger.viewModel.info("PDF navigator doesn't support preferences yet")
      return
    }

    let epubPrefs = preferences.toEPUBPreferences()
    epubNavigator.submitPreferences(epubPrefs)
  }

  private func navigateToSearchResult(locator: Locator) {
    guard let navigator else { return }

    Task {
      await navigator.go(to: locator, options: NavigatorGoOptions(animated: true))
      AppLogger.viewModel.info("Navigated to search result")
    }
  }

  private func highlightSearchResult(locator: Locator) {
    guard let decorableNavigator = navigator as? DecorableNavigator else {
      return
    }

    let decoration = Decoration(
      id: "selectedSearchResult",
      locator: locator,
      style: .highlight(tint: .yellow, isActive: false)
    )

    decorableNavigator.apply(decorations: [decoration], in: "search")
    AppLogger.viewModel.info("Applied search result highlight")
  }

  private func clearSearchHighlights() {
    guard let decorableNavigator = navigator as? DecorableNavigator else {
      return
    }

    decorableNavigator.apply(decorations: [], in: "search")
    AppLogger.viewModel.info("Cleared search highlights")
  }

  private func syncProgressToServer(_ progress: Double) {
    guard let bookID else { return }

    var location = navigator?.currentLocation
    location?.locations.totalProgression = nil

    let ebookLocation = location?.jsonString

    try? MediaProgress.updateEbookProgress(
      for: bookID,
      ebookProgress: progress,
      ebookLocation: ebookLocation
    )

    let now = Date()
    if let lastUpdate = lastProgressUpdate, now.timeIntervalSince(lastUpdate) < 1.0 {
      return
    }

    lastProgressUpdate = now

    Task {
      do {
        try await audiobookshelf.books.updateEbookProgress(
          bookID: bookID,
          progress: progress,
          location: ebookLocation
        )
        AppLogger.viewModel.debug("Synced ebook progress: \(progress)")
      } catch {
        AppLogger.viewModel.error("Failed to sync ebook progress: \(error)")
      }
    }
  }
}

extension EbookReaderViewModel {
  enum EbookError: Error {
    case unsupportedURL
    case unsupportedFormat
    case downloadFailed
  }
}

extension EbookReaderViewModel {
  private func downloadEbook(bookID: String, remoteURL: URL) async throws -> URL {
    DownloadManager.shared.startDownload(for: bookID, type: .ebook)

    for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
      if let path = updatedItem.ebookLocalPath {
        return path
      }
    }

    throw EbookError.downloadFailed
  }

  private func downloadTemporaryFile(from url: URL) async throws -> URL {
    let (tempURL, _) = try await URLSession.shared.download(from: url)

    let tempDirectory = FileManager.default.temporaryDirectory
    let fileName = url.lastPathComponent
    let destinationURL = tempDirectory.appendingPathComponent(fileName)

    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

    return destinationURL
  }

  private func cleanupTemporaryFile() {
    guard let tempURL = temporaryFileURL else { return }

    do {
      if FileManager.default.fileExists(atPath: tempURL.path) {
        try FileManager.default.removeItem(at: tempURL)
        AppLogger.viewModel.info("Cleaned up temporary ebook file")
      }
    } catch {
      AppLogger.viewModel.error("Failed to cleanup temporary file: \(error)")
    }

    temporaryFileURL = nil
  }
}

extension EbookReaderViewModel: EPUBNavigatorDelegate, PDFNavigatorDelegate, CBZNavigatorDelegate {
  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    updateProgress()
    updateCurrentChapterIndex()
    syncProgressToServer(progress)
  }

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    AppLogger.viewModel.error("Navigator error: \(error)")
  }
}
