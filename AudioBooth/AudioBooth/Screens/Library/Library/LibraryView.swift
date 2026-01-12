import SwiftUI

struct LibraryView: View {
  enum DisplayMode {
    case grid
    case list
  }

  let books: [BookCard.Model]
  let displayMode: DisplayMode
  var hasMorePages: Bool = false
  var onLoadMore: (() -> Void)?

  var body: some View {
    switch displayMode {
    case .grid:
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 100), spacing: 20)],
        spacing: 20
      ) {
        ForEach(books) { book in
          BookCard(model: book)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }

        if hasMorePages {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding()
            .onAppear {
              onLoadMore?()
            }
        }
      }
    case .list:
      LazyVStack(spacing: 12) {
        ForEach(books) { book in
          BookCard(model: book)
        }

        if hasMorePages {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding()
            .onAppear {
              onLoadMore?()
            }
        }
      }
    }
  }
}

#Preview("LibraryView - Empty") {
  LibraryView(books: [], displayMode: .grid)
}

#Preview("LibraryView - Grid") {
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
      title: "The Foundation The Foundation",
      details: "Isaac Asimov",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")
    ),
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

  ScrollView {
    LibraryView(books: sampleBooks, displayMode: .grid)
      .padding()
  }
}

#Preview("LibraryView - List") {
  let sampleBooks: [BookCard.Model] = [
    BookCard.Model(
      title: "The Lord of the Rings",
      details: "J.R.R. Tolkien",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
      author: "J.R.R. Tolkien",
      narrator: "Rob Inglis",
      publishedYear: "1954"
    ),
    BookCard.Model(
      title: "Dune",
      details: "Frank Herbert",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
      author: "Frank Herbert",
      narrator: "Scott Brick, Orlagh Cassidy",
      publishedYear: "1965"
    ),
    BookCard.Model(
      title: "The Foundation",
      details: "Isaac Asimov",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
      author: "Isaac Asimov",
      narrator: "Scott Brick",
      publishedYear: "1951"
    ),
  ]

  ScrollView {
    LibraryView(books: sampleBooks, displayMode: .list)
      .padding()
  }
}
