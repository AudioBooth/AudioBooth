import API
import Combine
import Foundation
import Models
import SafariServices
import UIKit

final class BookDetailsViewModel: BookDetailsView.Model {
  private let booksService: BooksService
  private let downloadManager: DownloadManager
  private let playerManager: PlayerManager

  private var cancellables = Set<AnyCancellable>()
  private var progressObservation: Task<Void, Never>?
  private var itemObservation: Task<Void, Never>?

  init(bookID: String) {
    self.booksService = Audiobookshelf.shared.books
    self.downloadManager = DownloadManager.shared
    self.playerManager = PlayerManager.shared

    super.init(bookID: bookID)
  }

  isolated deinit {
    progressObservation?.cancel()
    itemObservation?.cancel()
  }

  override func onAppear() {
    Task {
      await loadBookDetails()
    }
    setupDownloadStateBinding()
    setupProgressObservation()
    setupItemObservation()
  }

  private func loadBookDetails() async {
    do {
      let book = try await booksService.fetch(id: bookID)
      let mediaProgress = try? MediaProgress.fetch(bookID: bookID)

      self.title = book.title
      self.authors = book.media.metadata.authors?.map { Author(id: $0.id, name: $0.name) } ?? []
      self.series =
        book.series?.map { series in
          Series(id: series.id, name: series.name, sequence: series.sequence)
        } ?? []
      self.coverURL = book.coverURL
      self.chapters = book.chapters?.map { Chapter(from: $0) }
      self.isEbook = book.mediaType == .ebook

      self.tracks = []

      self.durationText = Duration.seconds(book.duration).formatted(
        .units(
          allowed: [.hours, .minutes],
          width: .narrow
        )
      )

      if let progress = mediaProgress {
        let remainingTime = book.duration * (1.0 - progress.progress)
        if remainingTime > 0 && progress.progress > 0 && progress.progress < 1.0 {
          self.timeRemaining = Duration.seconds(remainingTime).formatted(
            .units(
              allowed: [.hours, .minutes],
              width: .narrow
            )
          )
        }
      }

      self.isLoading = false
    } catch {
      self.isLoading = false
      Toast(error: "Failed to load book details").show()
    }
  }

  private func setupDownloadStateBinding() {
    downloadManager.$downloadProgress
      .map { [weak self] progress in
        guard let self = self else { return .notDownloaded }

        if let downloadProgress = progress[self.bookID] {
          return .downloading(progress: downloadProgress)
        }

        return .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
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

  override func onPlayTapped() {
    Task {
      do {
        let book = try await booksService.fetch(id: bookID)

        if book.mediaType == .ebook {
          openEbookInSafari(book)
        } else {
          await MainActor.run {
            playerManager.setCurrent(book)
            playerManager.showFullPlayer()
          }
        }
      } catch {
        Toast(error: "Failed to start playback").show()
      }
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
      downloadManager.cancelDownload(for: bookID)
    case .downloaded:
      downloadManager.deleteDownload(for: bookID)
    case .notDownloaded:
      Task {
        do {
          let book = try await booksService.fetch(id: bookID)
          downloadManager.startDownload(for: book.id)
        } catch {
          Toast(error: "Failed to start download").show()
        }
      }
    }
  }

  override func onMarkFinishedTapped() {
    Task {
      do {
        let book = try await booksService.fetch(id: bookID)
        let isFinished = (progress ?? 0) >= 1.0

        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: bookID, isFinished: !isFinished)

        try? MediaProgress.updateFinishedStatus(
          for: bookID, isFinished: !isFinished, duration: book.duration)

        Toast(success: isFinished ? "Marked as not finished" : "Marked as finished").show()
      } catch {
        Toast(error: "Failed to update finished status").show()
      }
    }
  }
}
