import API
import Combine
import Foundation
import Models

final class BookCardModel: BookCard.Model {
  struct Options: OptionSet {
    let rawValue: Int
    static let ignorePrefix = Options(rawValue: 1 << 0)
    static let showSequence = Options(rawValue: 1 << 1)
  }

  enum Item {
    case local(LocalBook)
    case remote(Book)
  }
  private let item: Item
  private var downloadStateCancellable: AnyCancellable?

  init(_ item: LocalBook, options: Options = []) {
    let id = item.bookID

    self.item = .local(item)

    var details = Duration.seconds(item.duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    )

    let size = item.tracks.reduce(0) { $0 + ($1.size ?? 0) }
    if size > 0 {
      details += " • \(size.formatted(.byteCount(style: .file)))"
    }

    let cover = Cover.Model(
      url: item.coverURL,
      title: item.title,
      author: item.authorNames,
      progress: MediaProgress.progress(for: id)
    )

    super.init(
      id: id,
      title: item.title,
      details: details,
      cover: cover,
      sequence: options.contains(.showSequence) ? item.series.first?.sequence : nil,
      author: item.authorNames,
      publishedYear: item.publishedYear,
      hasEbook: item.ebookFile != nil
    )

    setupDownloadProgressObserver()

    contextMenu = BookCardContextMenuModel(
      item,
      onProgressChanged: { [weak self] progress in
        self?.cover.progress = progress
      }
    )
  }

  init(
    _ item: Book,
    sortBy: SortBy?,
    options: Options = []
  ) {
    let title: String
    if sortBy == .title, options.contains(.ignorePrefix) {
      title = item.titleIgnorePrefix
    } else {
      title = item.title
    }

    let sequence = options.contains(.showSequence) ? item.series?.first?.sequence : nil
    let author = item.authorName
    let narrator = item.media.metadata.narratorName
    let publishedYear = item.publishedYear

    let time: Date.FormatStyle.TimeStyle = UserPreferences.shared.libraryDisplayMode == .row ? .shortened : .omitted

    let details: String?
    switch sortBy {
    case .publishedYear:
      details = item.publishedYear.map({ "Published \($0)" })
    case .title, .authorName, .authorNameLF:
      details = nil
    case .addedAt:
      details = "Added \(item.addedAt.formatted(date: .numeric, time: time))"
    case .updatedAt:
      details = "Updated \(item.updatedAt.formatted(date: .numeric, time: time))"
    case .size:
      details = item.size.map { "Size \($0.formatted(.byteCount(style: .file)))" }
    case .duration:
      details = Duration.seconds(item.duration).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
      )
    case .progress:
      if let mediaProgress = try? MediaProgress.fetch(bookID: item.id) {
        details = "Progress: \(mediaProgress.lastUpdate.formatted(date: .numeric, time: time))"
      } else {
        details = nil
      }
    case .progressFinishedAt:
      if let mediaProgress = try? MediaProgress.fetch(bookID: item.id), mediaProgress.isFinished {
        let date = mediaProgress.finishedAt ?? mediaProgress.lastUpdate
        details = "Finished \(date.formatted(date: .numeric, time: time))"
      } else {
        details = nil
      }
    case .progressCreatedAt:
      if let mediaProgress = try? MediaProgress.fetch(bookID: item.id) {
        details = "Started \(mediaProgress.lastPlayedAt.formatted(date: .numeric, time: time))"
      } else {
        details = nil
      }
    default:
      details = nil
    }

    self.item = .remote(item)

    let cover = Cover.Model(
      url: item.coverURL(),
      title: title,
      author: author,
      progress: MediaProgress.progress(for: item.id)
    )

    super.init(
      id: item.id,
      title: title,
      details: details,
      cover: cover,
      sequence: sequence,
      author: author,
      narrator: narrator,
      publishedYear: publishedYear,
      hasEbook: item.media.ebookFile != nil || item.media.ebookFormat != nil
    )

    setupDownloadProgressObserver()

    contextMenu = BookCardContextMenuModel(
      item,
      onProgressChanged: { [weak self] progress in
        self?.cover.progress = progress
      }
    )
  }

  private func setupDownloadProgressObserver() {
    downloadStateCancellable = DownloadManager.shared.$downloadStates
      .sink { [weak self] states in
        guard let self else { return }
        if case .downloading(let progress) = states[self.id] {
          self.cover.downloadProgress = progress
        } else {
          self.cover.downloadProgress = nil
        }
      }
  }

  override func onAppear() {
    cover.progress = MediaProgress.progress(for: id)
  }
}
