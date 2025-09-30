import Audiobookshelf
import Foundation
import SafariServices
import UIKit

final class BookCardModel: BookCard.Model {
  private var playerManager = PlayerManager.shared
  private var downloadManager = DownloadManager.shared

  private let book: Book
  private var progressObservationTask: Task<Void, Never>?

  init(_ item: Book, sortBy: BooksService.SortBy?) {
    let id = item.id

    let details: String?
    switch sortBy {
    case .publishedYear:
      details = item.publishedYear.map({ "Published \($0)" })
    case .title, .authorName, .authorNameLF:
      details = item.authorName
    case .addedAt:
      details =
        "Added \(DateFormatter.localizedString(from: item.addedAt, dateStyle: .short, timeStyle: .none))"
    case .updatedAt:
      details =
        "Updated \(DateFormatter.localizedString(from: item.updatedAt, dateStyle: .short, timeStyle: .none))"
    case .size:
      details = item.size.map {
        "Size \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))"
      }
    case .duration:
      details = Duration.seconds(item.duration).formatted(
        .units(
          allowed: [.hours, .minutes, .seconds],
          width: .narrow
        )
      )
    case nil:
      details = nil
    }

    self.book = item

    super.init(
      id: id,
      title: item.title,
      details: details,
      coverURL: item.coverURL,
      sequence: item.sequence,
      progress: (try? MediaProgress.fetch(bookID: id))?.progress
    )

    startObservingProgress()
  }

  isolated deinit {
    progressObservationTask?.cancel()
  }

  private func startObservingProgress() {
    let id = book.id
    progressObservationTask = Task { [weak self] in
      for await mediaProgress in MediaProgress.observe(bookID: id) {
        self?.progress = mediaProgress?.progress
      }
    }
  }

  override func onTapped() {
    switch book.media {
    case .audiobook:
      playerManager.setCurrent(book)
    case .ebook:
      openEbookInSafari()
    }
  }

  private func openEbookInSafari() {
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
    downloadManager.startDownload(for: book)
  }

  override func onMarkFinishedTapped(isFinished: Bool) {
    Task {
      do {
        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: book.id, isFinished: isFinished)
        try? MediaProgress.updateFinishedStatus(
          for: book.id, isFinished: isFinished, duration: book.duration)
        ToastManager.shared.show(
          success: isFinished ? "Marked as finished" : "Marked as not finished")
      } catch {
        ToastManager.shared.show(error: "Failed to update finished status")
      }
    }
  }

}
