import API
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
    withObservationTracking {
      _ = preferences.fontSize
      _ = preferences.fontFamily
      _ = preferences.theme
      _ = preferences.pageMargins
      _ = preferences.lineSpacing
    } onChange: { [weak self] in
      RunLoop.current.perform {
        guard let self else { return }
        self.applyPreferences(self.preferences)
        self.observeChanges()
      }
    }
  }

  override func onAppear() {
    Task {
      await loadEbook()
    }
  }

  private func loadEbook() async {
    do {
      isLoading = true
      error = nil

      let url: AbsoluteURL
      switch source {
      case .local(let localURL):
        guard let httpURL = FileURL(url: localURL) else { throw EbookError.unsupportedURL }
        url = httpURL

      case .remote(let remoteURL):
        guard let httpURL = HTTPURL(url: remoteURL) else { throw EbookError.unsupportedURL }
        url = httpURL
      }

      let asset = try await assetRetriever.retrieve(url: url).get()

      let publication = try await publicationOpener.open(
        asset: asset,
        allowUserInteraction: false
      ).get()

      self.publication = publication

      let httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
      self.httpServer = httpServer

      let progress: Double
      if let bookID {
        progress = MediaProgress.progress(for: bookID)
      } else {
        progress = 0.0
      }

      let initialLocation = await publication.locate(progression: progress)
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

    if let toc = try? await publication.tableOfContents().get() {
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

  override func onPreferencesChanged(_ preferences: EbookReaderPreferences) {
    AppLogger.viewModel.info("Applying preferences")
    applyPreferences(preferences)
  }

  private func applyPreferences(_ preferences: EbookReaderPreferences) {
    guard let epubNavigator = navigator as? EPUBNavigatorViewController else {
      AppLogger.viewModel.info("PDF navigator doesn't support preferences yet")
      return
    }

    let epubPrefs = preferences.toEPUBPreferences()
    epubNavigator.submitPreferences(epubPrefs)
  }

  private func syncProgressToServer(_ progress: Double) {
    guard let bookID else { return }

    try? MediaProgress.updateProgress(
      for: bookID,
      currentTime: 0,
      duration: 0,
      progress: progress
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
          progress: progress
        )
        AppLogger.viewModel.debug("Synced ebook progress: \(progress)")
      } catch {
        AppLogger.viewModel.error("Failed to sync ebook progress: \(error)")
      }
    }
  }

  enum EbookError: Error {
    case unsupportedURL
    case unsupportedFormat
  }
}

extension EbookReaderViewModel: EPUBNavigatorDelegate, PDFNavigatorDelegate {
  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    updateProgress()
    updateCurrentChapterIndex()
    syncProgressToServer(progress)
  }

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    AppLogger.viewModel.error("Navigator error: \(error)")
  }
}
