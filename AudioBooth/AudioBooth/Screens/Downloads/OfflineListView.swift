import Combine
import SwiftUI

struct OfflineListView: View {
  @ObservedObject var model: Model

  var body: some View {
    content
  }

  var content: some View {
    Group {
      if model.isLoading && model.books.isEmpty {
        ProgressView("Loading offline books...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.books.isEmpty {
        ContentUnavailableView(
          "No Downloaded Books",
          systemImage: "arrow.down.circle",
          description: Text("Books you download will appear here.")
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
    .searchable(text: $model.searchText, prompt: "Filter books")
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
            if !model.selectedBookIDs.isEmpty {
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
                model.selectedBookIDs.count == model.books.count ? "Unselect All" : "Select All",
                systemImage: model.selectedBookIDs.count == model.books.count
                  ? "circle" : "checkmark.circle"
              )
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .disabled(model.books.isEmpty)
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
            HStack(spacing: 12) {
              if let coverURL = group.coverURL {
                Cover(url: coverURL)
                  .frame(width: 60, height: 60)
              }

              VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(.primary)

                Text("^[\(group.books.count) book](inflect: true)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
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
    .environment(\.bookCardDisplayMode, .row)
  }

  @ViewBuilder
  private func bookRow(_ book: BookCard.Model) -> some View {
    HStack(spacing: 12) {
      if model.editMode == .active {
        Button {
          model.onSelectBook(id: book.id)
        } label: {
          Image(
            systemName: model.selectedBookIDs.contains(book.id) ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(model.selectedBookIDs.contains(book.id) ? Color.accentColor : .secondary)
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

  var id: String {
    switch self {
    case .book(let model): return model.id
    case .series(let group): return group.id
    }
  }
}

struct SeriesGroup: Identifiable {
  let id: String
  let name: String
  let books: [BookCard.Model]
  let coverURL: URL?
}

extension OfflineListView {
  @Observable
  class Model: ObservableObject {
    var books: [BookCard.Model]
    var items: [OfflineListItem]
    var isLoading: Bool
    var isPerformingBatchAction: Bool
    var editMode: EditMode
    var selectedBookIDs: Set<String>
    var searchText: String
    var isGroupedBySeries: Bool

    func onAppear() {}
    func onEditModeTapped() {}
    func onSelectBook(id: String) {}
    func onDeleteSelected() {}
    func onMarkFinishedSelected() {}
    func onResetProgressSelected() {}
    func onSelectAllTapped() {}
    func onReorder(from: IndexSet, to: Int) {}
    func onDelete(at: IndexSet) {}
    func onGroupSeriesToggled() {}

    init(
      books: [BookCard.Model] = [],
      items: [OfflineListItem] = [],
      isLoading: Bool = false,
      isPerformingBatchAction: Bool = false,
      editMode: EditMode = .inactive,
      selectedBookIDs: Set<String> = [],
      searchText: String = "",
      isGroupedBySeries: Bool = false
    ) {
      self.books = books
      self.items = items
      self.isLoading = isLoading
      self.isPerformingBatchAction = isPerformingBatchAction
      self.editMode = editMode
      self.selectedBookIDs = selectedBookIDs
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

#Preview("OfflineListView - With Books") {
  let sampleBooks: [BookCard.Model] = [
    BookCard.Model(
      title: "The Lord of the Rings",
      details: "J.R.R. Tolkien",
      cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
    ),
    BookCard.Model(
      title: "Dune",
      details: "Frank Herbert",
      cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
    ),
    BookCard.Model(
      title: "The Foundation",
      details: "Isaac Asimov",
      cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
    ),
  ]

  NavigationStack {
    OfflineListView(model: .init(books: sampleBooks))
  }
}

#Preview("OfflineListView - Edit Mode") {
  let sampleBooks: [BookCard.Model] = [
    BookCard.Model(
      title: "The Lord of the Rings",
      details: "J.R.R. Tolkien",
      cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
    ),
    BookCard.Model(
      title: "Dune",
      details: "Frank Herbert",
      cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
    ),
  ]

  NavigationStack {
    OfflineListView(
      model: .init(
        books: sampleBooks,
        editMode: .active,
        selectedBookIDs: [sampleBooks[0].id]
      )
    )
  }
}
