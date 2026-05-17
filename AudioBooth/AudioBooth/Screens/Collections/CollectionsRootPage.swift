import API
import Combine
import SwiftUI

struct CollectionsRootPage: View {
  @Environment(\.appTheme) var theme
  enum CollectionType: CaseIterable {
    case series
    case collections
    case playlists

    var next: CollectionType {
      let all = CollectionType.allCases
      let index = all.firstIndex(of: self) ?? 0
      return all[(index + 1) % all.count]
    }
  }

  @ObservedObject var model: Model
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  var body: some View {
    NavigationStack(path: $model.path) {
      CollectionsRootContent(selected: $model.selected)
        .id(libraries.current?.id)
        .background(theme.colors.background.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Picker("Collection Type", selection: $model.selected) {
              Text("Series").tag(CollectionType.series)
              Text("Collections").tag(CollectionType.collections)
              Text("Playlists").tag(CollectionType.playlists)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .tint(.primary)
            .fixedSize(horizontal: true, vertical: true)
          }
        }
        .navigationDestination(for: NavigationDestination.self) { $0.resolvedView }
    }
  }
}

private struct CollectionsRootContent: View {
  @Binding var selected: CollectionsRootPage.CollectionType

  @StateObject private var series = SeriesPageModel()
  @StateObject private var collections = CollectionsPageModel(mode: .collections)
  @StateObject private var playlists = CollectionsPageModel(mode: .playlists)

  var body: some View {
    switch selected {
    case .series:
      SeriesPage(model: series)
    case .collections:
      CollectionsPage(model: collections)
    case .playlists:
      CollectionsPage(model: playlists)
    }
  }
}

extension CollectionsRootPage {
  @Observable
  class Model: ObservableObject {
    var selected: CollectionType = .series
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

#Preview {
  CollectionsRootPage(model: CollectionsRootPage.Model())
}
