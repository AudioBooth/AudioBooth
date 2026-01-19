import Models
import SwiftUI

struct DownloadsRootPage: View {
  enum DownloadTab: Hashable {
    case downloaded
    case downloading
  }

  @State private var selectedTab: DownloadTab = .downloaded
  @ObservedObject private var downloadManager = DownloadManager.shared

  private var hasDownloadingBooks: Bool {
    !downloadManager.downloadInfos.isEmpty
  }

  var body: some View {
    NavigationStack {
      VStack {
        if selectedTab == .downloaded || !hasDownloadingBooks {
          OfflineListView(model: OfflineListViewModel())
        } else {
          DownloadingListView(model: DownloadingListViewModel())
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if hasDownloadingBooks {
          ToolbarItem(placement: .principal) {
            Picker("Download Tab", selection: $selectedTab) {
              Text("Downloaded").tag(DownloadTab.downloaded)
              Text("Downloading").tag(DownloadTab.downloading)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .font(.subheadline)
            .tint(.primary)
          }
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .author(let id, let name):
          AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name))
        case .series, .narrator, .genre, .tag:
          LibraryPage(model: LibraryPageModel(destination: destination))
        case .playlist(let id):
          CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
        case .collection(let id):
          CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .collections))
        case .offline, .stats:
          EmptyView()
        }
      }
    }
    .onChange(of: hasDownloadingBooks) { _, hasDownloading in
      if !hasDownloading {
        selectedTab = .downloaded
      }
    }
  }
}
