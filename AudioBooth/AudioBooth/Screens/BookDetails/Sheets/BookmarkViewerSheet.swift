import Combine
import SwiftUI

struct BookmarkViewerSheet: View {
  @Environment(\.dismiss) var dismiss

  @ObservedObject var model: Model
  @FocusState private var isTextFieldFocused: Bool
  @State private var editingBookmark: BookmarkRow.Model?
  @State private var editTitle: String = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if model.bookmarks.isEmpty {
          emptyStateView
        } else {
          listView
        }

        if let time = model.currentTime, model.bookmarks.allSatisfy({ $0.time != time }) {
          createFieldView(time)
        }
      }
      .navigationTitle("Your Bookmarks")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .tint(.primary)
        }
      }
      .onAppear {
        model.onAppear()
      }
      .alert(
        "Edit Bookmark",
        isPresented: Binding(
          get: { editingBookmark != nil },
          set: { if !$0 { editingBookmark = nil } }
        )
      ) {
        TextField("Bookmark title", text: $editTitle)
        Button("Cancel", role: .cancel) {
          editingBookmark = nil
        }
        Button("Save") {
          if let editingBookmark {
            editingBookmark.title = editTitle
            model.onEditBookmark(editingBookmark)
            self.editingBookmark = nil
          }
        }
      } message: {
        Text("Enter a new title for this bookmark")
      }
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      ContentUnavailableView(
        "No bookmarks",
        systemImage: "bookmark",
        description: Text(
          model.currentTime != nil
            ? "Create your first bookmark below."
            : "You haven't created any bookmarks for this book yet."
        )
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var listView: some View {
    List {
      ForEach(model.bookmarks) { bookmark in
        Button(action: {
          model.onSelectBookmark(bookmark)
        }) {
          HStack(spacing: 12) {
            BookmarkRow(model: bookmark)

            Spacer()

            Button(action: {
              editingBookmark = bookmark
              editTitle = bookmark.title
            }) {
              Image(systemName: "pencil")
                .foregroundStyle(Color.accentColor)
                .font(.body)
            }
            .buttonStyle(.plain)

            Button(action: {
              model.onDeleteBookmark(bookmark)
            }) {
              Image(systemName: "trash")
                .foregroundStyle(.red)
                .font(.body)
            }
            .buttonStyle(.plain)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          Button(
            role: .destructive,
            action: {
              model.onDeleteBookmark(bookmark)
            }
          ) {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
  }

  private func createFieldView(_ time: Int) -> some View {
    VStack(spacing: 0) {
      Divider()

      HStack(spacing: 12) {
        Text(
          Duration.seconds(time).formatted(.time(pattern: .hourMinuteSecond))
        )
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(minWidth: 60, alignment: .trailing)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)

        TextField("Bookmark title", text: $model.newBookmarkTitle)
          .textFieldStyle(.roundedBorder)
          .focused($isTextFieldFocused)
          .submitLabel(.done)
          .onSubmit {
            model.onCreateBookmark()
          }

        Button(action: {
          model.onCreateBookmark()
        }) {
          Text("Create")
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
    }
  }
}

extension BookmarkViewerSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    var isPresented: Bool
    var bookmarks: [BookmarkRow.Model]
    var newBookmarkTitle: String
    var currentTime: Int?

    func onAppear() {}
    func onSelectBookmark(_ bookmark: BookmarkRow.Model) {}
    func onEditBookmark(_ bookmark: BookmarkRow.Model) {}
    func onDeleteBookmark(_ bookmark: BookmarkRow.Model) {}
    func onCreateBookmark() {}

    init(
      isPresented: Bool = false,
      bookmarks: [BookmarkRow.Model] = [],
      newBookmarkTitle: String = "",
      currentTime: Int? = nil
    ) {
      self.isPresented = isPresented
      self.bookmarks = bookmarks
      self.newBookmarkTitle = newBookmarkTitle
      self.currentTime = currentTime
    }
  }
}

extension BookmarkViewerSheet.Model {
  static var mockReadonly: BookmarkViewerSheet.Model {
    let sampleBookmarks: [BookmarkRow.Model] = [
      BookmarkRow.Model(
        title: "Important Scene",
        time: 125,
        createdAt: Date().addingTimeInterval(-3600)
      ),
      BookmarkRow.Model(
        title: "Chapter 15 Start",
        time: 82858,
        createdAt: Date().addingTimeInterval(-86400)
      ),
      BookmarkRow.Model(
        title: "Interesting part",
        time: 3,
        createdAt: Date()
      ),
    ]

    return BookmarkViewerSheet.Model(
      bookmarks: sampleBookmarks
    )
  }

  static var mockEditable: BookmarkViewerSheet.Model {
    let sampleBookmarks: [BookmarkRow.Model] = [
      BookmarkRow.Model(
        title: "11/08/2025",
        time: 13,
        createdAt: Date().addingTimeInterval(-86400)
      ),
      BookmarkRow.Model(
        title: "qwerty",
        time: 3,
        createdAt: Date().addingTimeInterval(-3600)
      ),
      BookmarkRow.Model(
        title: "bookmark",
        time: 82858,
        createdAt: Date()
      ),
    ]

    return BookmarkViewerSheet.Model(
      bookmarks: sampleBookmarks,
      currentTime: 1500
    )
  }
}

#Preview("BookmarkViewerSheet - Readonly With Bookmarks") {
  BookmarkViewerSheet(model: .mockReadonly)
}

#Preview("BookmarkViewerSheet - Editable With Bookmarks") {
  BookmarkViewerSheet(model: .mockEditable)
}
