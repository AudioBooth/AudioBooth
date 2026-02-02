import API
import Combine
import SwiftUI

struct CollectionsPage: View {
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

  private var emptyStateTitle: String {
    switch model.mode {
    case .playlists:
      return String(localized: "No Playlists")
    case .collections:
      return String(localized: "No Collections")
    }
  }

  private var emptyStateMessage: String {
    switch model.mode {
    case .playlists:
      return String(localized: "Create your first playlist to get started.")
    case .collections:
      return String(localized: "No collections available.")
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView(
      emptyStateTitle,
      systemImage: "music.note.list",
      description: Text(emptyStateMessage)
    )
  }

  private var listView: some View {
    List {
      ForEach(model.collections) { collection in
        NavigationLink(value: model.navigationDestination(for: collection.id)) {
          CollectionRow(model: collection)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
      }
      .onDelete { indexSet in
        model.onDelete(at: indexSet)
      }
      .deleteDisabled(!model.canDelete)

      if model.hasMorePages {
        ProgressView()
          .frame(maxWidth: .infinity)
          .onAppear {
            model.loadNextPageIfNeeded()
          }
      }
    }
    .listStyle(.plain)
  }
}

extension CollectionsPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var collections: [CollectionRow.Model]
    var hasMorePages: Bool
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

    return CollectionsPage.Model(collections: sampleCollections)
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
