import SwiftUI

struct LibraryView: View {
  enum DisplayMode {
    case grid
    case list
  }

  let items: [Item]
  let displayMode: DisplayMode
  var hasMorePages: Bool = false
  var pageLoadFailed: Bool = false
  var onLoadMore: (() -> Void)?
  var isSelecting: Bool = false
  var selectedIDs: [String] = []
  var onToggleSelection: ((String) -> Void)?

  @ObservedObject private var preferences = UserPreferences.shared

  @ScaledMetric(relativeTo: .title) private var gridMinimum: CGFloat = 100

  var body: some View {
    switch displayMode {
    case .grid:
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: gridMinimum), spacing: 20)],
        spacing: 20
      ) {
        ForEach(items) { item in
          itemView(for: item)
            .frame(
              maxWidth: .infinity,
              maxHeight: .infinity,
              alignment: preferences.cardCoverDynamicRatio ? .bottom : .top
            )
        }

        if hasMorePages {
          PaginationFooter(hasError: pageLoadFailed) {
            onLoadMore?()
          }
        }
      }
    case .list:
      LazyVStack(spacing: 12) {
        ForEach(items) { item in
          itemView(for: item)
        }

        if hasMorePages {
          PaginationFooter(hasError: pageLoadFailed) {
            onLoadMore?()
          }
        }
      }
    }
  }

  @ViewBuilder
  private func itemView(for item: Item) -> some View {
    switch item {
    case .book(let model):
      if isSelecting {
        BookSelectCard(
          model: model,
          isSelected: selectedIDs.contains(model.id),
          onTap: { onToggleSelection?(model.id) }
        )
      } else {
        BookCard(model: model)
      }
    case .series(let model):
      SeriesCard(model: model)
        .opacity(isSelecting ? 0.4 : 1)
        .allowsHitTesting(!isSelecting)
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
        title: "Foundation",
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
        title: "Foundation",
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
