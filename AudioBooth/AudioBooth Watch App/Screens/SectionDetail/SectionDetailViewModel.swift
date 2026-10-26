import Foundation

final class SectionDetailViewModel: SectionDetailView.Model {
  private let connectivityManager = WatchConnectivityManager.shared

  init(section: WatchHomeSection) {
    super.init(sectionID: section.id, title: section.name)
  }

  override func onLoad() async {
    guard rows.isEmpty else { return }

    state = .loading

    guard connectivityManager.isReachable else {
      state = .error(String(localized: "iPhone not reachable.\nOpen AudioBooth on your iPhone and try again."))
      return
    }

    guard let section = await connectivityManager.fetchSection(sectionID: id) else {
      state = .error(String(localized: "Failed to load books."))
      return
    }

    let progress = connectivityManager.progress
    let bookRows = section.books.map { book in
      var updatedBook = book
      if let currentTime = progress[book.id] {
        updatedBook.currentTime = currentTime
      }
      return ContinueListeningRowModel(book: updatedBook)
    }
    let podcastRows = section.podcasts.map { podcast in
      ContinueListeningRow.Model(
        id: podcast.id,
        title: podcast.title,
        author: podcast.author,
        coverURL: podcast.coverURL,
        podcast: podcast
      )
    }
    rows = bookRows + podcastRows
    state = .loaded
  }
}
