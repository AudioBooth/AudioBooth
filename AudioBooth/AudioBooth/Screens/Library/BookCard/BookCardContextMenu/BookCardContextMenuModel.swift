import API
import Foundation
import Models

final class BookCardContextMenuModel: BookCardContextMenu.Model {
  enum Item {
    case local(LocalBook)
    case remote(Book)
  }

  private let item: Item
  private let onProgressChanged: ((Double) -> Void)?
  private let onRemoveFromContinueListening: (() -> Void)?

  init(
    _ item: LocalBook,
    onProgressChanged: ((Double) -> Void)? = nil,
    onRemoveFromContinueListening: (() -> Void)? = nil
  ) {
    self.item = .local(item)
    self.onProgressChanged = onProgressChanged
    self.onRemoveFromContinueListening = onRemoveFromContinueListening

    let authorInfo: BookCard.Author? = {
      guard let firstAuthor = item.authors.first else { return nil }
      return BookCard.Author(id: firstAuthor.id, name: firstAuthor.name)
    }()

    let narratorInfo: BookCard.Narrator? = {
      guard let firstNarrator = item.narrators.first else { return nil }
      return BookCard.Narrator(name: firstNarrator)
    }()

    let seriesInfo: BookCard.Series? = {
      guard let firstSeries = item.series.first else { return nil }
      return BookCard.Series(id: firstSeries.id, name: firstSeries.name)
    }()

    let downloadState = DownloadManager.shared.downloadStates[item.bookID] ?? .notDownloaded

    let progress = MediaProgress.progress(for: item.bookID)

    var actions: BookCardContextMenu.Model.Actions = []
    if progress > 0 {
      actions.insert(.resetProgress)
    }
    if progress < 1.0 {
      actions.insert(.markAsFinished)
    }
    if onRemoveFromContinueListening != nil {
      actions.insert(.removeFromContinueListening)
    }

    super.init(
      downloadState: downloadState,
      actions: actions,
      authorInfo: authorInfo,
      narratorInfo: narratorInfo,
      seriesInfo: seriesInfo
    )
  }

  init(
    _ item: Book,
    onProgressChanged: ((Double) -> Void)? = nil,
    onRemoveFromContinueListening: (() -> Void)? = nil
  ) {
    self.item = .remote(item)
    self.onProgressChanged = onProgressChanged
    self.onRemoveFromContinueListening = onRemoveFromContinueListening

    lazy var filterData = Audiobookshelf.shared.libraries.getCachedFilterData()

    let authorInfo: BookCard.Author? = {
      if let firstAuthor = item.media.metadata.authors?.first {
        return BookCard.Author(id: firstAuthor.id, name: firstAuthor.name)
      } else if let authorName = item.authorName {
        let name = authorName.split(separator: ",").first.map {
          String($0.trimmingCharacters(in: .whitespaces))
        }
        if let name,
          let filterData,
          let author = filterData.authors.first(where: { $0.name == name })
        {
          return BookCard.Author(id: author.id, name: author.name)
        }
      }
      return nil
    }()

    let narratorInfo: BookCard.Narrator? = {
      if let firstNarrator = item.media.metadata.narrators?.first {
        return BookCard.Narrator(name: firstNarrator)
      } else if let narratorName = item.media.metadata.narratorName {
        let name = narratorName.split(separator: ",").first.map {
          String($0.trimmingCharacters(in: .whitespaces))
        }
        if let name {
          return BookCard.Narrator(name: name)
        }
      }
      return nil
    }()

    let seriesInfo: BookCard.Series? = {
      if let firstSeries = item.series?.first {
        return BookCard.Series(id: firstSeries.id, name: firstSeries.name)
      } else if let seriesName = item.media.metadata.seriesName {
        let name = seriesName.split(separator: ",").first.map {
          String($0.trimmingCharacters(in: .whitespaces))
        }
        if let name {
          let cleanedName: String
          if let hashIndex = name.range(of: " #") {
            cleanedName = String(name[..<hashIndex.lowerBound])
          } else {
            cleanedName = name
          }

          if let filterData,
            let series = filterData.series.first(where: { $0.name == cleanedName })
          {
            return BookCard.Series(id: series.id, name: series.name)
          }
        }
      }
      return nil
    }()

    let downloadState = DownloadManager.shared.downloadStates[item.id] ?? .notDownloaded

    let progress = MediaProgress.progress(for: item.id)

    var actions: BookCardContextMenu.Model.Actions = []
    if progress > 0 {
      actions.insert(.resetProgress)
    }
    if progress < 1.0 {
      actions.insert(.markAsFinished)
    }
    if onRemoveFromContinueListening != nil {
      actions.insert(.removeFromContinueListening)
    }

    super.init(
      downloadState: downloadState,
      actions: actions,
      authorInfo: authorInfo,
      narratorInfo: narratorInfo,
      seriesInfo: seriesInfo
    )
  }

  override func onAppear() {
    var bookID: String

    switch item {
    case .local(let localBook):
      bookID = localBook.bookID
    case .remote(let book):
      bookID = book.id
    }

    let progress = MediaProgress.progress(for: bookID)

    downloadState = DownloadManager.shared.downloadStates[bookID] ?? .notDownloaded

    var updatedActions: BookCardContextMenu.Model.Actions = []
    if progress > 0 {
      updatedActions.insert(.resetProgress)
    }
    if progress < 1.0 {
      updatedActions.insert(.markAsFinished)
    }
    if onRemoveFromContinueListening != nil {
      updatedActions.insert(.removeFromContinueListening)
    }
    actions = updatedActions
  }

  override func onDownloadTapped() {
    switch item {
    case .local(let localBook):
      try? localBook.download()
    case .remote(let book):
      try? book.download()
    }
  }

  override func onCancelDownloadTapped() {
    switch item {
    case .local(let localBook):
      DownloadManager.shared.cancelDownload(for: localBook.bookID)
    case .remote(let book):
      DownloadManager.shared.cancelDownload(for: book.id)
    }
  }

  override func onRemoveDownloadTapped() {
    switch item {
    case .local(let localBook):
      localBook.removeDownload()
    case .remote(let book):
      book.removeDownload()
    }
  }

  override func onPlayTapped() {
    switch item {
    case .local(let localBook):
      localBook.play()
    case .remote(let book):
      book.play()
    }
  }

  override func onMarkAsFinishedTapped() {
    Task {
      switch item {
      case .local(let localBook):
        try? await localBook.markAsFinished()
      case .remote(let book):
        try? await book.markAsFinished()
      }
      onProgressChanged?(1)
    }
  }

  override func onResetProgressTapped() {
    Task {
      switch item {
      case .local(let localBook):
        try? await localBook.resetProgress()
      case .remote(let book):
        try? await book.resetProgress()
      }
      onProgressChanged?(0)
    }
  }

  override func onRemoveFromContinueListeningTapped() {
    guard let onRemoveFromContinueListening else { return }

    let bookID: String
    switch item {
    case .local(let localBook):
      bookID = localBook.bookID
    case .remote(let book):
      bookID = book.id
    }

    guard
      let progress = try? MediaProgress.fetch(bookID: bookID),
      let id = progress.id
    else { return }

    Task {
      try? await Audiobookshelf.shared.sessions.removeFromContinueListening(id)
      onRemoveFromContinueListening()
    }
  }
}
