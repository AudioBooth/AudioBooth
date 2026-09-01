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

struct ZoomDestination: Hashable {
  let destination: NavigationDestination
  let sourceID: String
}

extension EnvironmentValues {
  @Entry var zoomNamespace: Namespace.ID? = nil
}

struct DestinationLink<Label: View>: View {
  let destination: NavigationDestination
  let zooms: Bool
  @ViewBuilder let label: () -> Label

  @Environment(\.zoomNamespace) private var namespace
  @State private var sourceID = UUID().uuidString

  var body: some View {
    if #available(iOS 18.0, *), zooms, destination.isZoomable, let namespace {
      NavigationLink(value: ZoomDestination(destination: destination, sourceID: sourceID), label: label)
        .matchedTransitionSource(id: sourceID, in: namespace)
    } else {
      NavigationLink(value: destination, label: label)
    }
  }
}

extension View {
  func navigationDestinations() -> some View {
    navigationDestinations { $0.resolvedView }
  }

  func navigationDestinations(
    @ViewBuilder destination: @escaping (NavigationDestination) -> some View
  ) -> some View {
    modifier(NavigationDestinationsModifier(destination: destination))
  }
}

private struct NavigationDestinationsModifier<Destination: View>: ViewModifier {
  let destination: (NavigationDestination) -> Destination

  @Namespace private var namespace

  func body(content: Content) -> some View {
    content
      .environment(\.zoomNamespace, namespace)
      .navigationDestination(for: NavigationDestination.self) { value in
        destination(value)
          .environment(\.zoomNamespace, namespace)
      }
      .navigationDestination(for: ZoomDestination.self) { value in
        zoomed(destination(value.destination), sourceID: value.sourceID)
          .environment(\.zoomNamespace, namespace)
      }
  }

  @ViewBuilder
  private func zoomed(_ view: some View, sourceID: String) -> some View {
    if #available(iOS 18.0, *) {
      view.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      view
    }
  }
}

extension NavigationDestination {
  var isZoomable: Bool {
    switch self {
    case .book, .podcast, .series:
      true
    case .author, .authorLibrary, .narrator, .genre, .tag, .playlist, .collection, .podcastFeed, .offline, .stats:
      false
    }
  }
}
