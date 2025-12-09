import API
import Combine
import Foundation
import Logging
import Models
import SafariServices
import UIKit

final class BookDetailsViewModel: BookDetailsView.Model {
  private var booksService: BooksService { Audiobookshelf.shared.books }
  private var miscService: MiscService { Audiobookshelf.shared.misc }
  private var downloadManager: DownloadManager { .shared }
  private var playerManager: PlayerManager { .shared }
  private var authenticationService: AuthenticationService { Audiobookshelf.shared.authentication }

  private var cancellables = Set<AnyCancellable>()
  private var progressObservation: Task<Void, Never>?
  private var itemObservation: Task<Void, Never>?

  private var book: Book?
  private var localBook: LocalBook?

  init(bookID: String) {
    let canManageCollections = Audiobookshelf.shared.authentication.permissions?.update == true
    super.init(
      bookID: bookID,
      canManageCollections: canManageCollections,
      tabs: []
    )
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

        updateUI(
          title: localBook.title,
          authors: authors,
          narrators: localBook.narrators,
          series: series,
          coverURL: localBook.coverURL,
          duration: localBook.duration,
          mediaType: nil,
          chapters: localBook.chapters,
          tracks: localBook.tracks
        )

        if localBook.isDownloaded {
          downloadState = .downloaded
        }

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

  private func loadBookFromAPI() async {
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
        .filter { $0.isSupplementary == true && $0.fileType == "ebook" }
        .map { libraryFile in
          BookDetailsView.Model.SupplementaryEbook(
            filename: libraryFile.metadata.filename,
            size: libraryFile.metadata.size,
            ino: libraryFile.ino
          )
        }

      updateUI(
        title: book.title,
        authors: authors,
        narrators: narrators,
        series: series,
        coverURL: book.coverURL,
        duration: book.duration,
        mediaType: book.mediaType,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        genres: book.genres,
        tags: book.tags,
        description: book.description ?? book.descriptionPlain,
        chapters: book.chapters?.map(Chapter.init(from:)),
        tracks: book.tracks?.map(Track.init(from:)),
        ebooks: ebooks
      )

      error = nil
      isLoading = false
    } catch {
      if localBook == nil {
        isLoading = false
        self.error = "Failed to load book details. Please check your connection and try again."
      }
    }
  }

  private func updateUI(
    title: String,
    authors: [Author],
    narrators: [String],
    series: [Series],
    coverURL: URL?,
    duration: TimeInterval,
    mediaType: Book.MediaType?,
    publisher: String? = nil,
    publishedYear: String? = nil,
    genres: [String]? = nil,
    tags: [String]? = nil,
    description: String? = nil,
    chapters: [Chapter]?,
    tracks: [Track]?,
    ebooks: [BookDetailsView.Model.SupplementaryEbook]? = nil
  ) {
    self.title = title
    self.authors = authors
    self.series = series
    self.narrators = narrators
    self.coverURL = coverURL
    self.publisher = publisher
    self.publishedYear = publishedYear
    self.genres = genres
    self.tags = tags
    self.description = description

    if let mediaType {
      self.isEbook = mediaType == .ebook
      self.ereaderDevices = miscService.ereaderDevices.compactMap(\.name)
    }

    self.durationText = Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )

    if let progress = try? MediaProgress.fetch(bookID: bookID) {
      let remainingTime = duration * (1.0 - progress.progress)
      if remainingTime > 0 && progress.progress > 0 && progress.progress < 1.0 {
        if let current = PlayerManager.shared.current,
          [book?.id, localBook?.bookID].contains(current.id)
        {
          self.timeRemaining = Duration.seconds(current.playbackProgress.totalTimeRemaining)
            .formatted(
              .units(
                allowed: [.hours, .minutes],
                width: .narrow
              )
            )
        } else {
          self.timeRemaining = Duration.seconds(remainingTime).formatted(
            .units(
              allowed: [.hours, .minutes],
              width: .narrow
            )
          )
        }
      }
    }

    if let book {
      self.bookmarks = BookmarkViewerSheetViewModel(item: .remote(book))
    } else if let localBook {
      self.bookmarks = BookmarkViewerSheetViewModel(item: .local(localBook))
    } else {
      self.bookmarks = nil
    }

    var tabs = [ContentTab]()

    if let chapters, !chapters.isEmpty {
      tabs.append(.chapters(chapters))
    }

    if let tracks, !tracks.isEmpty {
      tabs.append(.tracks(tracks))
    }

    if let ebooks, !ebooks.isEmpty {
      tabs.append(.ebooks(ebooks))
    }

    self.tabs = tabs
  }

  private func setupDownloadStateBinding() {
    downloadManager.$currentProgress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] progress in
        guard let self else { return }
        if let progress = progress[bookID] {
          self.downloadState = .downloading(progress: progress)
        } else if self.downloadState != .downloaded {
          self.downloadState = .notDownloaded
        }
      }
      .store(in: &cancellables)
  }

  private func setupItemObservation() {
    let bookID = bookID
    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
        if updatedItem.isDownloaded {
          self?.downloadState = .downloaded
        } else if self?.downloadState == .downloaded {
          self?.downloadState = .notDownloaded
        }
      }
    }
  }

  private func setupProgressObservation() {
    let bookID = bookID
    progressObservation = Task { [weak self] in
      for await mediaProgress in MediaProgress.observe(where: \.bookID, equals: bookID) {
        self?.progress = mediaProgress.progress
      }
    }
  }

  private func setupPlayerStateObservation() {
    playerManager.$current
      .receive(on: DispatchQueue.main)
      .sink { [weak self] current in
        guard let self else { return }
        self.observeIsPlaying(current)
      }
      .store(in: &cancellables)
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.id == bookID else {
      isCurrentlyPlaying = false
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
    isCurrentlyPlaying = isCurrentBook && isPlaying
  }

  override func onPlayTapped() {
    if let book {
      if book.mediaType == .ebook {
        openEbookInSafari(book)
      } else if playerManager.current?.id == bookID {
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

  private func openEbookInSafari(_ book: Book) {
    guard let ebookURL = book.ebookURL else { return }

    let safariViewController = SFSafariViewController(url: ebookURL)
    safariViewController.modalPresentationStyle = .overFullScreen

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootViewController = window.rootViewController
    {
      rootViewController.present(safariViewController, animated: true)
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
        progress = 1.0
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
        progress = 0
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

  override func onSupplementaryEbookTapped(_ ebook: BookDetailsView.Model.SupplementaryEbook) {
    guard let serverURL = Audiobookshelf.shared.serverURL,
      let token = Audiobookshelf.shared.authentication.server?.token
    else {
      Toast(error: "Unable to open ebook").show()
      return
    }

    var url = serverURL.appendingPathComponent("api/items/\(bookID)/file/\(ebook.ino)")
    switch token {
    case .legacy(let token):
      url.append(queryItems: [URLQueryItem(name: "token", value: token)])
    case .bearer(let accessToken, _, _):
      url.append(queryItems: [URLQueryItem(name: "token", value: accessToken)])
    }

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
