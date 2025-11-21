import Combine
import Foundation

final class ContinueListeningViewModel: ContinueListeningView.Model {
  private let connectivityManager = WatchConnectivityManager.shared
  private let localStorage = LocalBookStorage.shared
  private var cancellables = Set<AnyCancellable>()

  init() {
    super.init()
    setupObservers()
    updateAllRows()
  }

  private func setupObservers() {
    connectivityManager.$continueListeningBooks
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateAllRows()
      }
      .store(in: &cancellables)

    connectivityManager.$progress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateAllRows()
      }
      .store(in: &cancellables)

    localStorage.$books
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateAllRows()
      }
      .store(in: &cancellables)
  }

  private func updateAllRows() {
    let localBooks = localStorage.books
    let downloadedBooks = localBooks.filter { $0.isDownloaded }
    let progress = connectivityManager.progress

    let remoteBooks = connectivityManager.continueListeningBooks

    continueListeningRows = remoteBooks.map { book in
      if let localBook = downloadedBooks.first(where: { $0.id == book.id }) {
        return ContinueListeningRowModel(book: localBook)
      }
      var updatedBook = book
      if let currentTime = progress[book.id] {
        updatedBook.currentTime = currentTime
      }
      return ContinueListeningRowModel(book: updatedBook)
    }

    availableOfflineRows = downloadedBooks.map { book in
      ContinueListeningRowModel(book: book)
    }
  }
}
