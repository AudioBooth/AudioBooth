import API
import Combine
import SwiftUI

struct PodcastsRootPage: View {
  enum SectionType: CaseIterable {
    case podcasts
    case playlists

    var next: SectionType {
      let all = SectionType.allCases
      let index = all.firstIndex(of: self) ?? 0
      return all[(index + 1) % all.count]
    }
  }

  @ObservedObject var model: Model
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  var body: some View {
    NavigationStack(path: $model.path) {
      PodcastsRootContent(selected: $model.selected)
        .id(libraries.current?.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Picker("Section", selection: $model.selected) {
              Text("Podcasts").tag(SectionType.podcasts)
              Text("Playlists").tag(SectionType.playlists)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .font(.subheadline)
            .tint(.primary)
          }
        }
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .book(let id):
            BookDetailsView(model: BookDetailsViewModel(bookID: id))
          case .playlist(let id):
            CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
          default:
            EmptyView()
          }
        }
    }
  }
}

private struct PodcastsRootContent: View {
  @Binding var selected: PodcastsRootPage.SectionType

  @StateObject private var podcasts = PodcastLibraryPageModel()
  @StateObject private var playlists = CollectionsPageModel(mode: .playlists)

  var body: some View {
    switch selected {
    case .podcasts:
      LibraryPage(model: podcasts)
    case .playlists:
      CollectionsPage(model: playlists)
    }
  }
}

extension PodcastsRootPage {
  @Observable
  class Model: ObservableObject {
    var selected: SectionType = .podcasts
    var path = NavigationPath()

    func onTabItemTapped() {
      if path.isEmpty {
        selected = selected.next
      } else {
        path = NavigationPath()
      }
    }
  }
}
