import Foundation

final class SectionDetailViewModel: SectionDetailView.Model {
  private let connectivityManager = WatchConnectivityManager.shared

  init(section: WatchHomeSection) {
    super.init(sectionID: section.id, title: section.name)
  }

  override func onLoad() async {
    state = .loading

    guard connectivityManager.isReachable else {
      state = .error(String(localized: "iPhone not reachable.\nOpen AudioBooth on your iPhone and try again."))
      return
    }

    guard let books = await connectivityManager.fetchSectionBooks(sectionID: id) else {
      state = .error(String(localized: "Failed to load books."))
      return
    }

    let progress = connectivityManager.progress
    rows = books.map { book in
      var updatedBook = book
      if let currentTime = progress[book.id] {
        updatedBook.currentTime = currentTime
      }
      return ContinueListeningRowModel(book: updatedBook)
    }
    state = .loaded
  }
}
