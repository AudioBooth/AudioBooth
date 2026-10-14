import Combine
import SwiftUI

struct AssistiveAccessView: View {
  @StateObject var model: Model

  @ObservedObject private var playerManager = PlayerManager.shared

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Books")
        .assistiveAccessIcon(systemImage: "books.vertical.fill")
        .onAppear(perform: model.onAppear)
        .navigationDestination(isPresented: $playerManager.isShowingFullPlayer) {
          if let current = playerManager.current {
            AssistedPlayer(model: current, isAssistiveAccess: true)
          }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.books.isEmpty {
      ContentUnavailableView("No Downloaded Books", systemImage: "arrow.down.circle")
    } else {
      List(model.books) { book in
        Button(action: { model.onBookTapped(book) }) {
          row(for: book)
        }
      }
      .listStyle(.plain)
    }
  }

  private func row(for book: Model.Book) -> some View {
    HStack(spacing: 16) {
      Cover(url: book.coverURL, style: .plain)
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(3)

        if let author = book.author {
          Text(author)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }
}

extension AssistiveAccessView {
  @Observable
  class Model: ObservableObject {
    struct Book: Identifiable {
      let id: String
      let title: String
      let author: String?
      let coverURL: URL?
    }

    var books: [Book]

    func onAppear() {}
    func onBookTapped(_ book: Book) {}

    init(books: [Book] = []) {
      self.books = books
    }
  }
}

#Preview {
  AssistiveAccessView(
    model: .init(books: [
      .init(id: "1", title: "Sample Audiobook", author: "Sample Author", coverURL: nil)
    ])
  )
}
