import Combine
import Models
import SwiftUI

struct DownloadingListView: View {
  @StateObject var model: Model

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        ForEach(model.books) { book in
          NavigationLink(value: NavigationDestination.book(id: book.id)) {
            Row(book: book, onCancel: { model.onCancelDownload(bookID: book.id) })
          }
        }
      }
    }
    .navigationTitle("Downloading")
    .onAppear(perform: model.onAppear)
  }
}

extension DownloadingListView {
  struct Row: View {
    let book: BookItem
    let onCancel: () -> Void

    var body: some View {
      HStack(spacing: 12) {
        cover

        VStack(alignment: .leading, spacing: 6) {
          Text(book.title)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .allowsTightening(true)

          if let details = book.details {
            Text(details)
              .font(.caption2)
              .lineLimit(1)
          }

          ProgressView(value: book.progress)
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: onCancel) {
          Image(systemName: "stop.circle")
            .font(.title2)
        }
        .buttonStyle(.plain)
      }
      .foregroundColor(.primary)
      .padding(.horizontal)
      .contentShape(Rectangle())
    }

    var cover: some View {
      CoverImage(url: book.coverURL)
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(.gray.opacity(0.3), lineWidth: 1)
        )
    }
  }
}

extension DownloadingListView {
  struct BookItem: Identifiable {
    let id: String
    let title: String
    let details: String?
    let coverURL: URL?
    var progress: Double
  }

  @Observable
  class Model: ObservableObject {
    var books: [BookItem]

    func onAppear() {}
    func onCancelDownload(bookID: String) {}

    init(books: [BookItem] = []) {
      self.books = books
    }
  }
}
