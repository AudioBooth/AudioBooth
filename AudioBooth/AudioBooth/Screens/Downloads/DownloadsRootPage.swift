import Models
import SwiftUI

struct DownloadsRootPage: View {
  enum DownloadTab: Hashable {
    case downloaded
    case downloading
  }
  @ObservedObject private var downloadManager = DownloadManager.shared

  @State private var selectedTab: DownloadTab = .downloaded

  @StateObject private var offline = OfflineListViewModel()
  @StateObject private var downloading = DownloadingListViewModel()

  private var hasDownloadingBooks: Bool {
    !downloadManager.downloadInfos.isEmpty
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
          ToolbarItem(placement: .principal) {
            Picker("Download Tab", selection: $selectedTab) {
              Text("Downloaded").tag(DownloadTab.downloaded)
              Text("Downloading").tag(DownloadTab.downloading)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .tint(.primary)
          }
        }
      }
      .navigationDestination(for: NavigationDestination.self) { $0.resolvedView }
    }
    .onChange(of: hasDownloadingBooks) { _, hasDownloading in
      if !hasDownloading {
        selectedTab = .downloaded
      }
    }
  }
}
