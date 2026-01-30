import API
import Combine
import Foundation
import Logging
import Models
import Nuke
import SafariServices
import UIKit

final class BookDetailsViewModel: BookDetailsView.Model {
  private var booksService: BooksService { Audiobookshelf.shared.books }
  private var sessionsService: SessionService { Audiobookshelf.shared.sessions }
  private var miscService: MiscService { Audiobookshelf.shared.misc }
  private var downloadManager: DownloadManager { .shared }
  private var playerManager: PlayerManager { .shared }
  private var authenticationService: AuthenticationService { Audiobookshelf.shared.authentication }

  private var cancellables = Set<AnyCancellable>()
  private var progressObservation: Task<Void, Never>?
  private var itemObservation: Task<Void, Never>?

  private var book: Book?
  private var localBook: LocalBook?

  var mediaProgress: MediaProgress? {
    didSet {
      progressChanged()
    }
  }

  init(bookID: String) {
    let initialMediaProgress = try? MediaProgress.fetch(bookID: bookID)
    super.init(
      bookID: bookID,
      progress: (initialMediaProgress?.progress ?? 0, initialMediaProgress?.ebookProgress ?? 0),
      isLoading: false,
      tabs: [],
      metadata: .init(),
      progressCard: initialMediaProgress.map { ProgressCard.Model($0) }
    )
    mediaProgress = initialMediaProgress
    updateActions()
  }

  isolated deinit {
    progressObservation?.cancel()
    itemObservation?.cancel()
  }

  override func onAppear() {
    Task {
      await loadLocalBook()
      await loadBookFromAPI()
    }
    setupDownloadStateBinding()
    setupProgressObservation()
    setupItemObservation()
    setupPlayerStateObservation()
    setupQueueObservation()
  }

  private func loadLocalBook() async {
    do {
      localBook = try LocalBook.fetch(bookID: bookID)

      if let localBook {
        let authors = localBook.authors.map { author in
          Author(id: author.id, name: author.name)
        }

        let series = localBook.series.map { series in
          Series(id: series.id, name: series.name, sequence: series.sequence)
        }

        var mediaType: Book.MediaType = []
        if !localBook.tracks.isEmpty {
          mediaType.insert(.audiobook)
        }
        if localBook.ebookFile != nil {
          mediaType.insert(.ebook)
        }

        let currentTime = MediaProgress.progress(for: bookID) * localBook.duration
        let chapters: [ChaptersContent.Chapter]?
        if !localBook.chapters.isEmpty {
          chapters = convertChapters(localBook.chapters, currentTime: currentTime)
        } else {
          chapters = nil
        }

        var flags: BookDetailsView.Model.Flags = []
        if localBook.isExplicit { flags.insert(.explicit) }
        if localBook.isAbridged { flags.insert(.abridged) }

        updateUI(
          title: localBook.title,
          subtitle: localBook.subtitle,
          authors: authors,
          narrators: localBook.narrators,
          series: series,
          coverURL: localBook.coverURL(raw: true),
          duration: localBook.duration,
          mediaType: mediaType,
          publisher: localBook.publisher,
          publishedYear: localBook.publishedYear,
          language: localBook.language,
          genres: localBook.genres,
          tags: localBook.tags,
          description: localBook.bookDescription,
          flags: flags,
          chapters: chapters,
          tracks: localBook.tracks
        )

        isLoading = false
      } else if book == nil {
        isLoading = true
      }
    } catch {
      AppLogger.viewModel.error("Failed to load local book: \(error)")
      if book == nil {
        isLoading = true
      }
    }
  }

  private func refreshCover() {
    Task {
      do {
        let request = ImageRequest(url: coverURL, options: .reloadIgnoringCachedData)
        _ = try await ImagePipeline.shared.image(for: request)
        let coverURL = self.coverURL
        self.coverURL = nil
        Task { @MainActor in
          self.coverURL = coverURL
        }
      } catch {}
    }
  }

  private func loadBookFromAPI() async {
    refreshCover()

    do {
      let book = try await booksService.fetch(id: bookID)
      self.book = book

      let authors =
        book.media.metadata.authors?.map { apiAuthor in
          Author(id: apiAuthor.id, name: apiAuthor.name)
        } ?? []

      let series =
        book.series?.map { apiSeries in
          Series(id: apiSeries.id, name: apiSeries.name, sequence: apiSeries.sequence)
        } ?? []

      let narrators = book.media.metadata.narrators ?? []

      let ebooks = book.libraryFiles?
        .filter { $0.fileType == .ebook }
        .map { libraryFile in
          EbooksContent.SupplementaryEbook(
            filename: libraryFile.metadata.filename,
            size: libraryFile.metadata.size,
            ino: libraryFile.ino
          )
        }

      var flags: BookDetailsView.Model.Flags = []
      if book.media.metadata.explicit == true {
        flags.insert(.explicit)
      }
      if book.media.metadata.abridged == true {
        flags.insert(.abridged)
      }

      let currentTime = mediaProgress?.currentTime ?? 0
      let chapters: [ChaptersContent.Chapter]?
      if let apiChapters = book.chapters {
        let modelChapters = apiChapters.map(Models.Chapter.init(from:))
        chapters = convertChapters(modelChapters, currentTime: currentTime)
      } else {
        chapters = nil
      }

      updateUI(
        title: book.title,
        subtitle: book.media.metadata.subtitle,
        authors: authors,
        narrators: narrators,
        series: series,
        coverURL: book.coverURL(raw: true),
        duration: book.duration,
        mediaType: book.mediaType,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        language: book.media.metadata.language,
        genres: book.genres,
        tags: book.tags,
        description: book.description ?? book.descriptionPlain,
        flags: flags,
        chapters: chapters,
        tracks: book.tracks?.map(Track.init(from:)),
        ebooks: ebooks
      )

      error = nil
      isLoading = false

      await loadSessions()
    } catch {
      if localBook == nil {
        isLoading = false
        self.error = "Failed to load book details. Please check your connection and try again."
      }
    }
  }

  private func loadSessions() async {
    do {
      let response = try await sessionsService.getListeningSessions(itemID: bookID)

      if !response.sessions.isEmpty {
        let bookDuration = book?.duration ?? localBook?.duration ?? 0
        let sessionsModel = SessionsContentModel(
          bookID: bookID,
          bookDuration: bookDuration,
          sessions: response.sessions,
          currentPage: response.page,
          numPages: response.numPages
        )
        tabs.append(.sessions(sessionsModel))
      }
    } catch {
      AppLogger.viewModel.error("Failed to load sessions: \(error)")
    }
  }

  private func updateUI(
    title: String,
    subtitle: String? = nil,
    authors: [Author],
    narrators: [String],
    series: [Series],
    coverURL: URL?,
    duration: TimeInterval,
    mediaType: Book.MediaType?,
    publisher: String? = nil,
    publishedYear: String? = nil,
    language: String? = nil,
    genres: [String]? = nil,
    tags: [String]? = nil,
    description: String? = nil,
    flags: BookDetailsView.Model.Flags = [],
    chapters: [ChaptersContent.Chapter]?,
    tracks: [Track]?,
    ebooks: [EbooksContent.SupplementaryEbook]? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.authors = authors
    self.series = series
    self.narrators = narrators
    self.coverURL = coverURL
    self.genres = genres
    self.tags = tags
    self.description = description
    self.flags = flags

    let hasAudio = mediaType?.contains(.audiobook) == true
    let isEbook = mediaType?.contains(.ebook) == true

    if isEbook {
      self.ereaderDevices = miscService.ereaderDevices.compactMap(\.name)
    }

    let durationText: String?
    if hasAudio {
      durationText = Duration.seconds(duration).formatted(
        .units(
          allowed: [.hours, .minutes],
          width: .narrow
        )
      )
    } else {
      durationText = nil
    }

    metadata.publisher = publisher
    metadata.publishedYear = publishedYear
    metadata.language = language
    metadata.durationText = durationText
    metadata.hasAudio = hasAudio
    metadata.isEbook = isEbook

    if let book {
      self.bookmarks = BookmarkViewerSheetViewModel(item: .remote(book))
    } else if let localBook {
      self.bookmarks = BookmarkViewerSheetViewModel(item: .local(localBook))
    } else {
      self.bookmarks = nil
    }

    var tabs = [ContentTab]()

    if let chapters, !chapters.isEmpty {
      let chaptersModel = ChaptersContentModel(
        chapters: chapters,
        book: book,
        localBook: localBook,
        bookID: bookID
      )
      tabs.append(.chapters(chaptersModel))
    }

    if let tracks, !tracks.isEmpty {
      let tracksModel = TracksContent.Model(tracks: tracks)
      tabs.append(.tracks(tracksModel))
    }

    if let ebooks, !ebooks.isEmpty {
      let ebooksModel = EbooksContentModel(
        ebooks: ebooks,
        bookID: bookID
      )
      tabs.append(.ebooks(ebooksModel))
    }

    self.tabs = tabs
    updateActions()
  }

  private func convertChapters(
    _ chapters: [Models.Chapter],
    currentTime: TimeInterval
  ) -> [ChaptersContent.Chapter] {
    chapters
      .sorted { $0.start < $1.start }
      .map { chapter in
        let status: ChaptersContent.Chapter.Status

        if currentTime >= chapter.end {
          status = .completed
        } else if currentTime >= chapter.start && currentTime < chapter.end {
          status = .current
        } else {
          status = .remaining
        }

        return ChaptersContent.Chapter(
          id: chapter.id,
          start: chapter.start,
          end: chapter.end,
          title: chapter.title,
          status: status
        )
      }
  }

  private func setupDownloadStateBinding() {
    downloadManager.$downloadStates
      .receive(on: DispatchQueue.main)
      .sink { [weak self] states in
        guard let self else { return }
        self.downloadState = states[bookID] ?? .notDownloaded
      }
      .store(in: &cancellables)
  }

  private func setupItemObservation() {
    let bookID = bookID
    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
        self?.localBook = updatedItem
      }
    }
  }

  private func setupProgressObservation() {
    let bookID = bookID
    progressObservation = Task { [weak self] in
      for await mediaProgress in MediaProgress.observe(where: \.bookID, equals: bookID) {
        self?.mediaProgress = mediaProgress
      }
    }
  }

  private func setupPlayerStateObservation() {
    playerManager.$current
      .receive(on: DispatchQueue.main)
      .sink { [weak self] current in
        guard let self else { return }
        self.observeIsPlaying(current)
        self.updateActions()
      }
      .store(in: &cancellables)
  }

  private func setupQueueObservation() {
    playerManager.$queue
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateActions()
      }
      .store(in: &cancellables)
  }

  private func updateActions() {
    var updatedActions: BookDetailsView.Model.Actions = []

    if authenticationService.permissions?.update == true {
      updatedActions.insert(.addToCollection)
    }

    if let bookmarks, !bookmarks.bookmarks.isEmpty {
      updatedActions.insert(.viewBookmarks)
    }

    if playerManager.current?.id != bookID {
      let isInQueue = playerManager.queue.contains { $0.bookID == bookID }
      updatedActions.insert(isInQueue ? .removeFromQueue : .addToQueue)
    }

    let currentProgress = progress.audio > 0 ? progress.audio : progress.ebook
    if currentProgress < 1.0 {
      updatedActions.insert(.markAsFinished)
    }
    if currentProgress > 0 {
      updatedActions.insert(.resetProgress)
    }

    if UserPreferences.shared.showNFCTagWriting {
      updatedActions.insert(.writeNFCTag)
    }

    if metadata.isEbook {
      updatedActions.insert(.openOnWeb)
      if !ereaderDevices.isEmpty {
        updatedActions.insert(.sendToEbook)
      }
    }

    actions = updatedActions
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.id == bookID else {
      isPlaying = false
      return
    }

    updatePlayingState()

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updatePlayingState()
        self.observeIsPlaying(playerManager.current)
      }
    }
  }

  private func updatePlayingState() {
    let isCurrentBook = playerManager.current?.id == bookID
    let isPlaying = playerManager.current?.isPlaying ?? false
    self.isPlaying = isCurrentBook && isPlaying
  }

  override func onPlayTapped() {
    if let book {
      if playerManager.current?.id == bookID {
        if let currentPlayer = playerManager.current as? BookPlayerModel {
          currentPlayer.onTogglePlaybackTapped()
        }
      } else {
        playerManager.setCurrent(book)
        PlayerManager.shared.play()
      }
    } else if let localBook {
      if playerManager.current?.id == bookID {
        if let currentPlayer = playerManager.current as? BookPlayerModel {
          currentPlayer.onTogglePlaybackTapped()
        }
      } else {
        playerManager.setCurrent(localBook)
        PlayerManager.shared.play()
      }
    } else {
      Toast(error: "Book not available").show()
    }
  }

  override func onReadTapped() {
    if let ebookURL = localBook?.ebookLocalPath {
      ebookReader = EbookReaderViewModel(source: .local(ebookURL), bookID: bookID)
    } else if let book, let ebookURL = book.ebookURL {
      ebookReader = EbookReaderViewModel(source: .remote(ebookURL), bookID: bookID)
    } else {
      Toast(error: "Ebook URL not available").show()
    }
  }

  override func onOpenTapped() {
    if let url = book?.ebookURL {
      openEbookInSafari(url)
    } else {
      Toast(error: "Unable to open ebook").show()
    }
  }

  override func onDownloadTapped() {
    switch downloadState {
    case .downloading:
      downloadState = .notDownloaded
      downloadManager.cancelDownload(for: bookID)

    case .downloaded:
      if let book {
        book.removeDownload()
      } else if let localBook {
        localBook.removeDownload()
      }
      downloadState = .notDownloaded

    case .notDownloaded:
      guard let book else {
        Toast(error: "Cannot download without network connection").show()
        return
      }
      downloadState = .downloading(progress: 0)
      try? book.download()
    }
  }

  override func onMarkFinishedTapped() {
    Task {
      do {
        if let book {
          try await book.markAsFinished()
        } else if let localBook {
          try await localBook.markAsFinished()
        }
        progress = (1.0, 1.0)
        updateActions()
        Toast(success: "Marked as finished").show()
      } catch {
        Toast(error: "Failed to mark as finished").show()
      }
    }
  }

  override func onResetProgressTapped() {
    Task {
      do {
        if let book {
          try await book.resetProgress()
        } else if let localBook {
          try await localBook.resetProgress()
        }
        progress = (0, 0)
        progressCard = nil
        updateActions()
        Toast(success: "Progress reset").show()
      } catch {
        Toast(error: "Failed to reset progress").show()
      }
    }
  }

  override func onWriteTagTapped() {
    Task {
      await NFCWriter.write(bookID: bookID)
    }
  }

  override func onSendToEbookTapped(_ device: String) {
    Task {
      do {
        try await miscService.sendEbookToDevice(itemID: bookID, deviceName: device)
        Toast(success: "Ebook sent to \(device)").show()
      } catch {
        Toast(error: "Unable to send ebook to \(device)").show()
      }
    }
  }

  override func onAddToQueueTapped() {
    if let book {
      playerManager.addToQueue(book)
    } else if let localBook {
      playerManager.addToQueue(localBook)
    }
    updateActions()
  }

  override func onRemoveFromQueueTapped() {
    if let book {
      playerManager.removeFromQueue(bookID: book.id)
    } else if let localBook {
      playerManager.removeFromQueue(bookID: localBook.bookID)
    }
    updateActions()
  }

}

extension BookDetailsViewModel {
  private func openEbookInSafari(_ url: URL) {
    let safariViewController = SFSafariViewController(url: url)
    safariViewController.modalPresentationStyle = .overFullScreen

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootViewController = window.rootViewController
    {
      rootViewController.present(safariViewController, animated: true)
    }
  }
}

extension BookDetailsViewModel {
  func progressChanged() {
    guard let mediaProgress else { return }

    Task { @MainActor in
      progress = (mediaProgress.progress, mediaProgress.ebookProgress ?? 0)
      progressCard = ProgressCard.Model(mediaProgress)
      updateChapterStatuses()
      updateActions()
    }
  }

  private func updateChapterStatuses() {
    let modelChapters: [Models.Chapter]
    if let localBook, !localBook.chapters.isEmpty {
      modelChapters = localBook.chapters
    } else if let book, let apiChapters = book.chapters {
      modelChapters = apiChapters.map(Models.Chapter.init(from:))
    } else {
      return
    }

    let currentTime = mediaProgress?.currentTime ?? 0
    let viewChapters = convertChapters(modelChapters, currentTime: currentTime)

    for tab in tabs {
      if case .chapters(let chaptersModel) = tab {
        chaptersModel.chapters = viewChapters
        break
      }
    }
  }
}
