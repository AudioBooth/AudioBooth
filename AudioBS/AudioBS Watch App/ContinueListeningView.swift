import Combine
import NukeUI
import SwiftUI

struct ContinueListeningView: View {
  @StateObject var model: Model
  @ObservedObject var connectivityManager = WatchConnectivityManager.shared

  var body: some View {
    Group {
      if model.isLoading && model.books.isEmpty {
        ProgressView()
      } else {
        content
      }
    }
    .navigationTitle("AudioBS")
    .task {
      await model.fetch()
    }
  }

  private var content: some View {
    ScrollView {
      VStack {
        ForEach(model.books) { item in
          Button {
            model.playBook(bookID: item.id)
          } label: {
            HStack(spacing: 12) {
              if let coverURL = item.coverURL {
                LazyImage(url: coverURL) { state in
                  if let image = state.image {
                    image
                      .resizable()
                      .aspectRatio(contentMode: .fill)
                  } else {
                    Color.gray
                  }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
              }

              VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                  .font(.caption2)
                  .fontWeight(.medium)
                  .lineLimit(2)
                  .frame(maxWidth: .infinity, alignment: .leading)

                if !item.author.isEmpty {
                  Text(item.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if item.timeRemaining > 0 {
                  Text(formatTimeRemaining(item.timeRemaining))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                }
              }
            }
            .padding()
            .background(Color(red: 0.1, green: 0.1, blue: 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
              RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.2, green: 0.2, blue: 0.4), lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
        }

        refresh
      }
    }
  }

  private var refresh: some View {
    Button {
      Task {
        await model.fetch()
      }
    } label: {
      Label("Refresh", systemImage: "arrow.clockwise")
    }
    .disabled(model.isLoading)
    .padding(.top)
  }

  private func formatTimeRemaining(_ duration: Double) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }
}

extension ContinueListeningView {
  @Observable class Model: ObservableObject {
    struct BookItem: Identifiable {
      let id: String
      let title: String
      let author: String
      let coverURL: URL?
      let timeRemaining: Double
    }

    var books: [BookItem]
    var isLoading: Bool

    func fetch() async {}
    func playBook(bookID: String) {}

    init(books: [BookItem] = [], isLoading: Bool = false) {
      self.books = books
      self.isLoading = isLoading
    }
  }
}

#Preview {
  NavigationStack {
    ContinueListeningView(
      model: ContinueListeningView.Model(
        books: [
          .init(
            id: "1",
            title: "The Lord of the Rings",
            author: "J.R.R. Tolkien",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            timeRemaining: 420
          ),
          .init(
            id: "2",
            title: "Dune",
            author: "Frank Herbert",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
            timeRemaining: 42000
          ),
          .init(
            id: "3",
            title: "The Foundation",
            author: "Isaac Asimov",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
            timeRemaining: 38000
          ),
        ]
      )
    )
  }
}
