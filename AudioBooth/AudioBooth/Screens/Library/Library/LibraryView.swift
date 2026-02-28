import SwiftUI

struct LibraryView: View {
  enum DisplayMode {
    case grid
    case list
  }

  let items: [Item]
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
        ForEach(items) { item in
          switch item {
          case .book(let model):
            BookCard(model: model)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          case .series(let model):
            SeriesCard(model: model)
              .environment(\.seriesCardDisplayMode, .card)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          }
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
        ForEach(items) { item in
          switch item {
          case .book(let model):
            BookCard(model: model)
          case .series(let model):
            SeriesCard(model: model)
          }
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

extension LibraryView {
  enum Item: Identifiable {
    case book(BookCard.Model)
    case series(SeriesCard.Model)

    var id: String {
      switch self {
      case .book(let model): model.id
      case .series(let model): model.id
      }
    }
  }
}

#Preview("LibraryView - Empty") {
  LibraryView(items: [], displayMode: .grid)
}

#Preview("LibraryView - Grid") {
  let sampleItems: [LibraryView.Item] = [
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
    .series(SeriesCard.Model.mock),
    .book(
      BookCard.Model(
        title: "The Foundation",
        details: "Isaac Asimov",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
      )
    ),
  ]

  ScrollView {
    LibraryView(items: sampleItems, displayMode: .grid)
      .padding()
  }
}

#Preview("LibraryView - List") {
  let sampleItems: [LibraryView.Item] = [
    .book(
      BookCard.Model(
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")),
        author: "J.R.R. Tolkien",
        narrator: "Rob Inglis",
        publishedYear: "1954"
      )
    ),
    .book(
      BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")),
        author: "Frank Herbert",
        narrator: "Scott Brick, Orlagh Cassidy",
        publishedYear: "1965"
      )
    ),
    .book(
      BookCard.Model(
        title: "The Foundation",
        details: "Isaac Asimov",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")),
        author: "Isaac Asimov",
        narrator: "Scott Brick",
        publishedYear: "1951"
      )
    ),
  ]

  ScrollView {
    LibraryView(items: sampleItems, displayMode: .list)
      .padding()
  }
}
