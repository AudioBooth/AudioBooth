import Combine
import SwiftUI

struct BookmarksSheet: View {
  @ObservedObject var model: Model

  var body: some View {
    List {
      Button(action: model.onAddTapped) {
        Label("Add Bookmark", systemImage: "bookmark")
      }

      ForEach(model.bookmarks) { bookmark in
        Button(action: { model.onBookmarkTapped(bookmark) }) {
          VStack(alignment: .leading, spacing: 4) {
            Text(bookmark.title)
              .font(.caption)
              .lineLimit(2)

            Text(verbatim: Duration.seconds(bookmark.time).formatted(.time(pattern: .hourMinuteSecond)))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
      }
    }
    .navigationTitle("Bookmarks")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
  }
}

extension BookmarksSheet {
  @Observable
  class Model: ObservableObject {
    var isPresented: Bool = false
    var bookmarks: [WatchBookmark]

    init(bookmarks: [WatchBookmark] = []) {
      self.bookmarks = bookmarks
    }

    func onAppear() {}
    func onAddTapped() {}
    func onBookmarkTapped(_ bookmark: WatchBookmark) {}
  }
}

#Preview {
  NavigationStack {
    BookmarksSheet(
      model: BookmarksSheet.Model(
        bookmarks: [
          WatchBookmark(time: 754, title: "11/9/2026 21:14"),
          WatchBookmark(time: 3610, title: "A passage to come back to"),
        ]
      )
    )
  }
}
