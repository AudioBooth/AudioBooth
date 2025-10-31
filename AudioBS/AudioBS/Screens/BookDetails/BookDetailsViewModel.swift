import API
import Combine
import Foundation
import Models
import OSLog
import SafariServices
import UIKit

final class BookDetailsViewModel: BookDetailsView.Model {
  private var booksService: BooksService { Audiobookshelf.shared.books }
  private var downloadManager: DownloadManager { .shared }
  private var playerManager: PlayerManager { .shared }

  private var cancellables = Set<AnyCancellable>()
  private var progressObservation: Task<Void, Never>?
  private var itemObservation: Task<Void, Never>?

  private var book: Book?
  private var localBook: LocalBook?

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
          chapters: localBook.chapters,
          mediaType: nil
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

      let displayDescription = convertToAttributedString(
        html: book.description,
        fallback: book.descriptionPlain
      )

      updateUI(
        title: book.title,
        authors: authors,
        narrators: narrators,
        series: series,
        coverURL: book.coverURL,
        duration: book.duration,
        chapters: book.chapters?.map { Chapter(from: $0) },
        mediaType: book.mediaType,
        publisher: book.publisher,
        publishedYear: book.publishedYear,
        genres: book.genres,
        tags: book.tags,
        description: displayDescription
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
    chapters: [Chapter]?,
    mediaType: Book.MediaType?,
    publisher: String? = nil,
    publishedYear: String? = nil,
    genres: [String]? = nil,
    tags: [String]? = nil,
    description: AttributedString? = nil
  ) {
    self.title = title
    self.authors = authors
    self.series = series
    self.narrators = narrators
    self.coverURL = coverURL
    self.chapters = chapters
    self.tracks = []
    self.publisher = publisher
    self.publishedYear = publishedYear
    self.genres = genres
    self.tags = tags
    self.description = description

    if let mediaType {
      self.isEbook = mediaType == .ebook
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
        self.timeRemaining = Duration.seconds(remainingTime).formatted(
          .units(
            allowed: [.hours, .minutes],
            width: .narrow
          )
        )
      }
    }
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

  private func convertToAttributedString(html: String?, fallback: String?) -> AttributedString? {
    guard
      let html,
      let nsAttributedString = try? NSAttributedString(
        data: Data(html.utf8),
        options: [
          .documentType: NSAttributedString.DocumentType.html,
          .characterEncoding: String.Encoding.utf8.rawValue,
        ],
        documentAttributes: nil
      ),
      var attributedString = try? AttributedString(nsAttributedString, including: \.uiKit)
    else { return fallback.map(AttributedString.init) }

    let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)

    for run in attributedString.runs {
      if let existingFont = attributedString[run.range].font {
        let traits = existingFont.fontDescriptor.symbolicTraits
        let descriptor =
          baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
        attributedString[run.range].font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
      }
      attributedString[run.range].foregroundColor = nil
    }

    return attributedString
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
        if let currentPlayer = playerManager.current as? BookPlayerModel {
          currentPlayer.onTogglePlaybackTapped()
        }
      }
    } else if let localBook {
      if playerManager.current?.id == bookID {
        if let currentPlayer = playerManager.current as? BookPlayerModel {
          currentPlayer.onTogglePlaybackTapped()
        }
      } else {
        playerManager.setCurrent(localBook)
        if let currentPlayer = playerManager.current as? BookPlayerModel {
          currentPlayer.onTogglePlaybackTapped()
        }
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
      downloadState = .notDownloaded
      downloadManager.deleteDownload(for: bookID)

    case .notDownloaded:
      if book == nil {
        Toast(error: "Cannot download without network connection").show()
        return
      }
      downloadState = .downloading(progress: 0)
      downloadManager.startDownload(for: bookID)
    }
  }

  override func onMarkFinishedTapped() {
    guard let duration = book?.duration ?? localBook?.duration else {
      Toast(error: "Book not available").show()
      return
    }

    Task {
      do {
        let isFinished = (progress ?? 0) >= 1.0

        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: bookID, isFinished: !isFinished)

        try? MediaProgress.updateFinishedStatus(
          for: bookID, isFinished: !isFinished, duration: duration)

        Toast(success: isFinished ? "Marked as not finished" : "Marked as finished").show()
      } catch {
        Toast(error: "Failed to update finished status").show()
      }
    }
  }
}
