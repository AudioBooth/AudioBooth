import Combine
import SwiftUI

struct OfflineListView: View {
  @ObservedObject var model: Model

  var body: some View {
    content
  }

  var content: some View {
    Group {
      if model.isLoading && model.items.isEmpty {
        ProgressView("Loading downloads...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.items.isEmpty {
        ContentUnavailableView(
          "No Downloads",
          systemImage: "arrow.down.circle",
          description: Text("Books and episodes you download will appear here.")
        )
      } else {
        list
      }
    }
    .overlay {
      if model.isPerformingBatchAction {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .overlay {
            ProgressView()
              .controlSize(.large)
              .tint(.white)
          }
      }
    }
    .navigationTitle("Downloaded")
    .searchable(text: $model.searchText, prompt: "Filter downloads")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          model.onGroupSeriesToggled()
        } label: {
          Image(systemName: model.isGroupedBySeries ? "rectangle.stack.fill" : "rectangle.stack")
        }
        .tint(.primary)
      }

      ToolbarItem(placement: .topBarTrailing) {
        Button(model.editMode == .active ? "Done" : "Select") {
          model.onEditModeTapped()
        }
        .tint(.primary)
      }

      if model.editMode == .active {
        if #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            if !model.selectedIDs.isEmpty {
              Button {
                model.onMarkFinishedSelected()
              } label: {
                Label("Mark Finished", systemImage: "checkmark.circle")
              }

              Button {
                model.onResetProgressSelected()
              } label: {
                Label("Reset Progress", systemImage: "arrow.counterclockwise")
              }

              Button(role: .destructive) {
                model.onDeleteSelected()
              } label: {
                Label("Remove Downloads", systemImage: "trash")
              }
              .tint(.red)

              Divider()
            }

            Button {
              model.onSelectAllTapped()
            } label: {
              Label(
                model.selectedIDs.count == model.selectableCount ? "Unselect All" : "Select All",
                systemImage: model.selectedIDs.count == model.selectableCount
                  ? "circle" : "checkmark.circle"
              )
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .disabled(model.selectableCount == 0)
          .tint(.primary)
        }
      }
    }
    .onAppear {
      model.onAppear()
    }
  }

  private var list: some View {
    List {
      ForEach(model.items) { item in
        switch item {
        case .book(let bookModel):
          bookRow(bookModel)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        case .series(let group):
          DisclosureGroup {
            ForEach(group.books) { book in
              bookRow(book)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
          } label: {
            groupLabel(name: group.name, count: group.books.count, coverURL: group.coverURL)
          }
          .listRowBackground(Color.clear)

        case .episode(let episodeModel):
          episodeRow(episodeModel)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        case .podcast(let group):
          DisclosureGroup {
            ForEach(group.episodes) { episode in
              episodeRow(episode)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
          } label: {
            groupLabel(name: group.name, count: group.episodes.count, coverURL: group.coverURL)
          }
          .listRowBackground(Color.clear)
        }
      }
      .onMove(
        perform: model.isGroupedBySeries
          ? nil
          : { from, to in
            model.onReorder(from: from, to: to)
          }
      )
      .onDelete(
        perform: model.editMode == .active || model.isGroupedBySeries
          ? nil
          : { indexSet in
            model.onDelete(at: indexSet)
          }
      )
    }
    .listStyle(.plain)
    .environment(\.editMode, $model.editMode)
    .environment(\.itemDisplayMode, .row)
  }

  private func groupLabel(name: String, count: Int, coverURL: URL?) -> some View {
    HStack(spacing: 12) {
      if let coverURL {
        Cover(url: coverURL)
          .frame(width: 60, height: 60)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(name)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        Text("^[\(count) item](inflect: true)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  private func episodeRow(_ episode: BookCard.Model) -> some View {
    HStack(spacing: 12) {
      if model.editMode == .active {
        Button {
          model.onSelectItem(id: episode.id)
        } label: {
          Image(
            systemName: model.selectedIDs.contains(episode.id) ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(model.selectedIDs.contains(episode.id) ? Color.accentColor : .secondary)
          .imageScale(.large)
        }
        .buttonStyle(.plain)
      }

      HStack(spacing: 12) {
        Cover(model: episode.cover, size: .small)
          .frame(width: 60, height: 60)

        VStack(alignment: .leading, spacing: 6) {
          Text(episode.title)
            .font(.caption)
            .foregroundColor(.primary)
            .fontWeight(.medium)
            .lineLimit(1)

          if let author = episode.author {
            Text(author)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          if let details = episode.details {
            Text(details)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .contentShape(Rectangle())
      .overlay {
        if model.editMode != .active {
          NavigationLink(
            value: NavigationDestination.podcast(id: episode.podcastID ?? episode.id, episodeID: episode.id)
          ) {}
          .opacity(0)
        }
      }
    }
  }

  @ViewBuilder
  private func bookRow(_ book: BookCard.Model) -> some View {
    HStack(spacing: 12) {
      if model.editMode == .active {
        Button {
          model.onSelectItem(id: book.id)
        } label: {
          Image(
            systemName: model.selectedIDs.contains(book.id) ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(model.selectedIDs.contains(book.id) ? Color.accentColor : .secondary)
          .imageScale(.large)
        }
        .buttonStyle(.plain)
      }

      BookListCard(model: book)
    }
  }
}

enum OfflineListItem: Identifiable {
  case book(BookCard.Model)
  case series(SeriesGroup)
  case episode(BookCard.Model)
  case podcast(PodcastGroup)

  var id: String {
    switch self {
    case .book(let model): return model.id
    case .series(let group): return group.id
    case .episode(let model): return model.id
    case .podcast(let group): return group.id
    }
  }
}

struct SeriesGroup: Identifiable {
  let id: String
  let name: String
  let books: [BookCard.Model]
  let coverURL: URL?
}

struct PodcastGroup: Identifiable {
  let id: String
  let name: String
  let episodes: [BookCard.Model]
  let coverURL: URL?
}

extension OfflineListView {
  @Observable
  class Model: ObservableObject {
    var items: [OfflineListItem]
    var selectableCount: Int
    var isLoading: Bool
    var isPerformingBatchAction: Bool
    var editMode: EditMode
    var selectedIDs: Set<String>
    var searchText: String
    var isGroupedBySeries: Bool

    func onAppear() {}
    func onEditModeTapped() {}
    func onSelectItem(id: String) {}
    func onDeleteSelected() {}
    func onMarkFinishedSelected() {}
    func onResetProgressSelected() {}
    func onSelectAllTapped() {}
    func onReorder(from: IndexSet, to: Int) {}
    func onDelete(at: IndexSet) {}
    func onGroupSeriesToggled() {}

    init(
      items: [OfflineListItem] = [],
      selectableCount: Int = 0,
      isLoading: Bool = false,
      isPerformingBatchAction: Bool = false,
      editMode: EditMode = .inactive,
      selectedIDs: Set<String> = [],
      searchText: String = "",
      isGroupedBySeries: Bool = false
    ) {
      self.items = items
      self.selectableCount = selectableCount
      self.isLoading = isLoading
      self.isPerformingBatchAction = isPerformingBatchAction
      self.editMode = editMode
      self.selectedIDs = selectedIDs
      self.searchText = searchText
      self.isGroupedBySeries = isGroupedBySeries
    }
  }
}

#Preview("OfflineListView - Loading") {
  NavigationStack {
    OfflineListView(model: .init(isLoading: true))
  }
}

#Preview("OfflineListView - Empty") {
  NavigationStack {
    OfflineListView(model: .init())
  }
}

#Preview("OfflineListView - With Items") {
  let sampleItems: [OfflineListItem] = [
    .book(
      BookCard.Model(
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
      )
    ),
    .book(
      BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
      )
    ),
    .episode(
      BookCard.Model(
        podcastID: "pod1",
        title: "Episode 1: The Beginning",
        details: "30min",
        author: "The Daily"
      )
    ),
  ]

  NavigationStack {
    OfflineListView(model: .init(items: sampleItems, selectableCount: 3))
  }
}

#Preview("OfflineListView - Edit Mode") {
  let sampleItems: [OfflineListItem] = [
    .book(
      BookCard.Model(
        id: "book1",
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
      )
    ),
    .book(
      BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
      )
    ),
  ]

  NavigationStack {
    OfflineListView(
      model: .init(
        items: sampleItems,
        selectableCount: 2,
        editMode: .active,
        selectedIDs: ["book1"]
      )
    )
  }
}
