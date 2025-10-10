import API
import Combine
import Foundation
import Models

final class BookCardModel: BookCard.Model {
  private var playerManager = PlayerManager.shared
  private var downloadManager = DownloadManager.shared

  enum Item {
    case local(LocalBook)
    case remote(Book)
  }
  private let item: Item

  private var progressObservationTask: Task<Void, Never>?
  private var localBookObservationTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  init(_ item: LocalBook) {
    let id = item.bookID

    self.item = .local(item)

    super.init(
      id: id,
      title: item.title,
      details: item.authorNames,
      coverURL: item.coverURL,
      sequence: item.series.first?.sequence
    )
  }

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

    self.item = .remote(item)

    super.init(
      id: id,
      title: item.title,
      details: details,
      coverURL: item.coverURL,
      sequence: item.series?.first?.sequence
    )
  }

  override func onAppear() {
    startObservingProgress()
    startObservingDownloadState()
    startObservingLocalBook()
  }

  override func onDisappear() {
    progressObservationTask?.cancel()
    localBookObservationTask?.cancel()
    cancellables.removeAll()
  }

  private func startObservingProgress() {
    let bookID = id
    progressObservationTask = Task { [weak self] in
      for await mediaProgress in MediaProgress.observe(where: \.bookID, equals: bookID) {
        self?.progress = mediaProgress.progress
      }
    }
  }

  private func startObservingDownloadState() {
    let bookID = id
    downloadManager.$downloadProgress
      .map { progress -> DownloadManager.DownloadState? in
        if let downloadProgress = progress[bookID] {
          return .downloading(progress: downloadProgress)
        }
        return nil
      }
      .sink { [weak self] downloadState in
        if let downloadState = downloadState {
          self?.downloadState = downloadState
        } else {
          self?.downloadState = .notDownloaded
        }
      }
      .store(in: &cancellables)
  }

  private func startObservingLocalBook() {
    let bookID = id
    localBookObservationTask = Task { [weak self] in
      for await updatedBook in LocalBook.observe(where: \.bookID, equals: bookID) {
        guard !Task.isCancelled, let self = self else { continue }

        if let progress = downloadManager.downloadProgress[bookID] {
          self.downloadState = .downloading(progress: progress)
        } else if updatedBook.isDownloaded {
          self.downloadState = .downloaded
        } else {
          self.downloadState = .notDownloaded
        }
      }
    }
  }

  override func onDownloadTapped() {
    downloadManager.startDownload(for: id)
    downloadState = .downloading(progress: 0)
  }

  override func onCancelDownloadTapped() {
    downloadManager.cancelDownload(for: id)
    downloadState = .notDownloaded
  }

  override func onRemoveFromDeviceTapped() {
    downloadManager.deleteDownload(for: id)

    if let localBook = try? LocalBook.fetch(bookID: id) {
      try? localBook.delete()
    }

    downloadState = .notDownloaded
  }

  override func onMarkFinishedTapped(isFinished: Bool) {
    Task {
      do {
        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: id,
          isFinished: isFinished
        )

        let duration: Double
        switch item {
        case .local(let book):
          duration = book.duration
        case .remote(let book):
          duration = book.duration
        }

        try? MediaProgress.updateFinishedStatus(
          for: id,
          isFinished: isFinished,
          duration: duration
        )

        Toast(
          success: isFinished ? "Marked as finished" : "Marked as not finished"
        ).show()
      } catch {
        Toast(error: "Failed to update finished status").show()
      }
    }
  }

}
