import Combine
import SwiftUI

struct OfflineListView: View {
  @ObservedObject var model: Model

  var body: some View {
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
        content
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
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          model.onGroupSeriesToggled()
        } label: {
          Image(systemName: model.isGroupedBySeries ? "rectangle.stack.fill" : "rectangle.stack")
        }
        .tint(.primary)
      }

      if #available(iOS 26.0, *) {
        ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
      }

      ToolbarItem(placement: .navigationBarTrailing) {
        Button(model.editMode == .active ? "Done" : "Select") {
          model.onEditModeTapped()
        }
        .tint(.primary)
      }

      if model.editMode == .active {
        if #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
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

  private var content: some View {
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
            ForEach(group.books) { seriesBook in
              bookRow(seriesBook.book, sequence: seriesBook.sequence)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
          } label: {
            HStack(spacing: 12) {
              if let coverURL = group.coverURL {
                CoverImage(url: coverURL)
                  .frame(width: 60, height: 60)
                  .clipShape(RoundedRectangle(cornerRadius: 6))
                  .overlay(
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(.gray.opacity(0.3), lineWidth: 1)
                  )
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
            .padding(.vertical, 8)
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
  }

  @ViewBuilder
  private func bookRow(_ book: BookCard.Model, sequence: String? = nil) -> some View {
    if model.editMode == .active {
      HStack(spacing: 12) {
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

        Row(book: book, sequence: sequence)
      }
    } else {
      NavigationLink(value: NavigationDestination.book(id: book.id)) {
        Row(book: book, sequence: sequence)
      }
      .buttonStyle(.plain)
    }
  }
}

extension OfflineListView {
  struct Row: View {
    let book: BookCard.Model
    let sequence: String?

    var body: some View {
      HStack(spacing: 12) {
        cover

        VStack(alignment: .leading, spacing: 6) {
          Text(book.title)
            .font(.caption)
            .foregroundColor(.primary)
            .fontWeight(.medium)
            .lineLimit(1)
            .allowsTightening(true)

          if let author = book.author {
            rowMetadata(icon: "pencil", value: author)
          }

          if let sequence = sequence {
            rowMetadata(icon: "number", value: sequence)
          } else if let narrator = book.narrator, !narrator.isEmpty {
            rowMetadata(icon: "person.wave.2.fill", value: narrator)
          }

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let publishedYear = book.publishedYear {
          Text(publishedYear)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .contentShape(Rectangle())
      .onAppear(perform: book.onAppear)
    }

    var cover: some View {
      CoverImage(url: book.coverURL)
        .overlay(alignment: .bottom) { progressBar }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(.gray.opacity(0.3), lineWidth: 1)
        )
    }

    func rowMetadata(icon: String, value: String) -> some View {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(value)
          .font(.caption2)
          .foregroundColor(.primary)
      }
      .lineLimit(1)
    }

    @ViewBuilder
    var progressBar: some View {
      if let progress = book.progress, progress > 0 {
        GeometryReader { geometry in
          let progressColor: Color = progress >= 1.0 ? .green : .orange

          Rectangle()
            .fill(progressColor)
            .frame(width: geometry.size.width * progress, height: 4)
        }
        .frame(height: 4)
      }
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

struct SeriesBookItem: Identifiable {
  let book: BookCard.Model
  let sequence: String

  var id: String { book.id }
}

struct SeriesGroup: Identifiable {
  let id: String
  let name: String
  let books: [SeriesBookItem]
  let coverURL: URL?

  var displayName: String {
    "\(name) (\(books.count) \(books.count == 1 ? "book" : "books"))"
  }
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
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
    ),
    BookCard.Model(
      title: "Dune",
      details: "Frank Herbert",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
    ),
    BookCard.Model(
      title: "The Foundation",
      details: "Isaac Asimov",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")
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
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
    ),
    BookCard.Model(
      title: "Dune",
      details: "Frank Herbert",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
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
