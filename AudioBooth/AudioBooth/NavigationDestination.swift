import Foundation
import SwiftUI

enum NavigationDestination: Hashable {
  case book(id: String)
  case podcast(id: String, episodeID: String? = nil)
  case series(id: String, name: String, libraryID: String? = nil)
  case author(id: String, name: String, libraryID: String? = nil)
  case authorLibrary(id: String, name: String, libraryID: String? = nil)
  case narrator(name: String, libraryID: String? = nil)
  case genre(name: String, libraryID: String? = nil)
  case tag(name: String, libraryID: String? = nil)
  case playlist(id: String)
  case collection(id: String)
  case podcastFeed(podcastID: String, podcastTitle: String, coverURL: URL?, feedURL: String)
  case offline
  case stats
}

extension NavigationDestination {
  @ViewBuilder
  var resolvedView: some View {
    switch self {
    case .book(let id):
      BookDetailsView(model: BookDetailsViewModel(bookID: id))
    case .podcast(let id, let episodeID):
      PodcastDetailsView(model: PodcastDetailsViewModel(podcastID: id, episodeID: episodeID))
    case .podcastFeed(let id, let podcastTitle, let coverURL, let feedURL):
      PodcastFeedView(
        model: PodcastFeedViewModel(
          podcastID: id,
          podcastTitle: podcastTitle,
          coverURL: coverURL,
          feedURL: feedURL
        )
      )
    case .author(let id, let name, let libraryID):
      AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name, libraryID: libraryID))
    case .series, .narrator, .genre, .tag, .authorLibrary:
      LibraryPage(model: LibraryPageModel(destination: self))
    case .playlist(let id):
      CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
    case .collection(let id):
      CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .collections))
    case .offline:
      OfflineListView(model: OfflineListViewModel())
    case .stats:
      StatsPageView(model: StatsPageViewModel())
    }
  }
}
