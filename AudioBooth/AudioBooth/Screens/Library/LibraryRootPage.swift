import API
import Combine
import SwiftUI

struct LibraryRootPage: View {
  @Environment(\.appTheme) var theme
  enum LibraryType: CaseIterable {
    case library
    case authors
    case narrators

    var next: LibraryType {
      let all = LibraryType.allCases
      let index = all.firstIndex(of: self) ?? 0
      return all[(index + 1) % all.count]
    }
  }

  @ObservedObject var model: Model
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  var body: some View {
    NavigationStack(path: $model.path) {
      LibraryRootContent(selected: $model.selected)
        .id(libraries.current?.id)
        .background(theme.colors.background.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            Picker("Library Type", selection: $model.selected) {
              Text("Library").tag(LibraryType.library)
              Text("Authors").tag(LibraryType.authors)
              Text("Narrators").tag(LibraryType.narrators)
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

private struct LibraryRootContent: View {
  @Binding var selected: LibraryRootPage.LibraryType

  @StateObject private var library = LibraryPageModel()
  @StateObject private var authors = AuthorsPageModel()
  @StateObject private var narrators = NarratorsPageModel()

  var body: some View {
    switch selected {
    case .library:
      LibraryPage(model: library)
    case .authors:
      AuthorsPage(model: authors)
    case .narrators:
      NarratorsPage(model: narrators)
    }
  }
}

extension LibraryRootPage {
  @Observable
  class Model: ObservableObject {
    var selected: LibraryType = .library
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
