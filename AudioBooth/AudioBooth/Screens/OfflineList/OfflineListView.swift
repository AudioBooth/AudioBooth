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
        Button(model.editMode == .active ? "Done" : "Select") {
          model.onEditModeTapped()
        }
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
        }
      }
    }
    .onAppear {
      model.onAppear()
    }
  }

  private var content: some View {
    List {
      ForEach(model.books) { book in
        bookRow(book)
      }
      .onMove { from, to in
        model.onReorder(from: from, to: to)
      }
      .onDelete(
        perform: model.editMode == .active
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
  private func bookRow(_ book: BookCard.Model) -> some View {
    if model.editMode == .active {
      HStack(spacing: 12) {
        Button {
          model.onSelectBook(id: book.id)
        } label: {
          Image(
            systemName: model.selectedBookIDs.contains(book.id) ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(model.selectedBookIDs.contains(book.id) ? .blue : .secondary)
          .imageScale(.large)
        }
        .buttonStyle(.plain)

        Row(book: book)
      }
    } else {
      NavigationLink(value: NavigationDestination.book(id: book.id)) {
        Row(book: book)
      }
      .buttonStyle(.plain)
    }
  }
}

extension OfflineListView {
  struct Row: View {
    let book: BookCard.Model

    var body: some View {
      HStack(spacing: 12) {
        CoverImage(url: book.coverURL)
          .overlay(alignment: .bottom) { progressBar }
          .frame(width: 60, height: 60)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(.gray.opacity(0.3), lineWidth: 1)
          )

        VStack(alignment: .leading, spacing: 6) {
          Text(book.title)
            .font(.body)
            .fontWeight(.medium)
            .lineLimit(2)

          if let author = book.author {
            HStack(spacing: 4) {
              Image(systemName: "pencil")
                .font(.caption2)
              Text(author)
                .font(.caption)
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
          }

          if let narrator = book.narrator {
            HStack(spacing: 4) {
              Image(systemName: "person.wave.2.fill")
                .font(.caption2)
              Text(narrator)
                .font(.caption)
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let publishedYear = book.publishedYear {
          Text(publishedYear)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
      .onAppear(perform: book.onAppear)
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

extension OfflineListView {
  @Observable
  class Model: ObservableObject {
    var books: [BookCard.Model]
    var isLoading: Bool
    var isPerformingBatchAction: Bool
    var editMode: EditMode
    var selectedBookIDs: Set<String>
    var searchText: String

    func onAppear() {}
    func onEditModeTapped() {}
    func onSelectBook(id: String) {}
    func onDeleteSelected() {}
    func onMarkFinishedSelected() {}
    func onResetProgressSelected() {}
    func onSelectAllTapped() {}
    func onReorder(from: IndexSet, to: Int) {}
    func onDelete(at: IndexSet) {}

    init(
      books: [BookCard.Model] = [],
      isLoading: Bool = false,
      isPerformingBatchAction: Bool = false,
      editMode: EditMode = .inactive,
      selectedBookIDs: Set<String> = [],
      searchText: String = ""
    ) {
      self.books = books
      self.isLoading = isLoading
      self.isPerformingBatchAction = isPerformingBatchAction
      self.editMode = editMode
      self.selectedBookIDs = selectedBookIDs
      self.searchText = searchText
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
