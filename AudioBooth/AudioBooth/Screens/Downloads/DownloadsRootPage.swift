import SwiftUI

struct DownloadsRootPage: View {
  @Environment(\.isPartiallyFolded) private var isPartiallyFolded

  enum DownloadTab: Hashable {
    case downloaded
    case downloading
  }

  @State private var selectedTab: DownloadTab = .downloaded

  @StateObject private var offline = OfflineListViewModel()
  @StateObject private var downloading = DownloadingListViewModel()

  private var hasDownloadingBooks: Bool {
    !downloading.books.isEmpty
  }

  var body: some View {
    NavigationStack {
      VStack {
        if selectedTab == .downloaded || !hasDownloadingBooks {
          OfflineListView(model: offline)
        } else {
          DownloadingListView(model: downloading)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if hasDownloadingBooks {
          ToolbarItem(placement: isPartiallyFolded ? .topBarLeading : .principal) {
            Picker("Download Tab", selection: $selectedTab) {
              Text("Downloaded").tag(DownloadTab.downloaded)
              Text("Downloading").tag(DownloadTab.downloading)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .tint(.primary)
          }
          .sharedBackgroundHidden()
        }
      }
      .navigationDestinations()
    }
    .onChange(of: hasDownloadingBooks) { _, hasDownloading in
      if !hasDownloading {
        selectedTab = .downloaded
      }
    }
  }
}
