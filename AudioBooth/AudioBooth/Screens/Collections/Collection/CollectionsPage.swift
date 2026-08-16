import API
import Combine
import SwiftUI

struct CollectionsPage: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    Group {
      if model.isLoading && model.collections.isEmpty {
        ProgressView("Loading...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.collections.isEmpty && !model.isLoading {
        emptyStateView
      } else {
        listView
      }
    }
    .refreshable {
      await model.refresh()
    }
    .onAppear {
      model.onAppear()
    }
  }

  private var emptyStateTitle: LocalizedStringResource {
    switch model.mode {
    case .playlists: "No Playlists"
    case .collections: "No Collections"
    }
  }

  private var emptyStateMessage: LocalizedStringResource {
    switch model.mode {
    case .playlists: "Create your first playlist to get started."
    case .collections: "No collections available."
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView(
      emptyStateTitle,
      systemImage: "music.note.list",
      description: Text(emptyStateMessage)
    )
  }

  private var countLabel: Text? {
    guard let total = model.totalCount else { return nil }
    switch model.mode {
    case .playlists:
      return Text("^[\(total) playlist](inflect: true)")
    case .collections:
      return Text("^[\(total) collection](inflect: true)")
    }
  }

  private var listView: some View {
    List {
      if let countLabel {
        countLabel
          .font(.title2.bold())
          .foregroundColor(.primary)
          .listRowSeparator(.hidden)
          .listRowBackground(theme.colors.background.page)
      }

      ForEach(model.collections) { collection in
        NavigationLink(value: model.navigationDestination(for: collection.id)) {
          CollectionRow(model: collection)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(theme.colors.background.page)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
      }
      .onDelete { indexSet in
        model.onDelete(at: indexSet)
      }
      .deleteDisabled(!model.canDelete)

      if model.hasMorePages {
        PaginationFooter(hasError: model.pageLoadFailed, onLoadMore: model.loadNextPageIfNeeded)
          .listRowBackground(theme.colors.background.page)
      }
    }
    .listRowSpacing(0.0)
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
  }
}

extension CollectionsPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var collections: [CollectionRow.Model]
    var hasMorePages: Bool
    var pageLoadFailed: Bool = false
    var totalCount: Int?
    var mode: CollectionMode
    var canDelete: Bool

    func onAppear() {}
    func refresh() async {}
    func onDelete(at indexSet: IndexSet) {}
    func loadNextPageIfNeeded() {}
    func navigationDestination(for id: String) -> NavigationDestination {
      switch mode {
      case .playlists:
        return .playlist(id: id)
      case .collections:
        return .collection(id: id)
      }
    }

    init(
      isLoading: Bool = false,
      collections: [CollectionRow.Model] = [],
      hasMorePages: Bool = false,
      mode: CollectionMode = .playlists,
      canDelete: Bool = true
    ) {
      self.isLoading = isLoading
      self.collections = collections
      self.hasMorePages = hasMorePages
      self.mode = mode
      self.canDelete = canDelete
    }
  }
}

extension CollectionsPage.Model: Hashable {
  static func == (lhs: CollectionsPage.Model, rhs: CollectionsPage.Model) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension CollectionsPage.Model {
  static var mock: CollectionsPage.Model {
    let sampleCollections: [CollectionRow.Model] = [
      CollectionRow.Model(
        id: "1",
        name: "My Favorites",
        description: "My favorite audiobooks",
        count: 5,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
        ]
      ),
      CollectionRow.Model(
        id: "2",
        name: "Science Fiction",
        description: nil,
        count: 12,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
        ]
      ),
      CollectionRow.Model(
        id: "3",
        name: "Currently Reading",
        description: "Books I'm actively listening to",
        count: 3,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!
        ]
      ),
    ]

    let model = CollectionsPage.Model(collections: sampleCollections)
    model.totalCount = sampleCollections.count
    return model
  }
}

#Preview("CollectionsPage - Loading") {
  NavigationStack {
    CollectionsPage(model: .init(isLoading: true))
  }
}

#Preview("CollectionsPage - Empty") {
  NavigationStack {
    CollectionsPage(model: .init())
  }
}

#Preview("CollectionsPage - With Collections") {
  NavigationStack {
    CollectionsPage(model: .mock)
  }
}
