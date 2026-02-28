import SwiftUI

struct SeriesView: View {
  let series: [SeriesCard.Model]
  let displayMode: SeriesCard.DisplayMode
  var hasMorePages: Bool = false
  var onLoadMore: (() -> Void)?

  private var columns: [GridItem] {
    switch displayMode {
    case .row:
      [GridItem(.adaptive(minimum: 250), spacing: 20)]
    case .card:
      [GridItem(.adaptive(minimum: 100), spacing: 20)]
    }
  }

  private var gridSpacing: CGFloat {
    20
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: gridSpacing) {
      ForEach(series, id: \.id) { series in
        SeriesCard(model: series)
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
    .environment(\.seriesCardDisplayMode, displayMode)
  }
}

#Preview("SeriesView - Empty") {
  SeriesView(series: [], displayMode: .row)
}

#Preview("SeriesView - Row") {
  let sampleSeries: [SeriesCard.Model] = [
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"), title: "Book 1"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"), title: "Book 2"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"), title: "Book 1")
      ]
    ),
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"), title: "Book 1"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"), title: "Book 2"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"), title: "Book 1")
      ]
    ),
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"), title: "Book 1"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"), title: "Book 2"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"), title: "Book 1")
      ]
    ),
  ]

  ScrollView {
    SeriesView(series: sampleSeries, displayMode: .row)
      .padding()
  }
}

#Preview("SeriesView - Card") {
  let sampleSeries: [SeriesCard.Model] = [
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"), title: "Book 1"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"), title: "Book 2"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"), title: "Book 3"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"), title: "Book 1")
      ]
    ),
    SeriesCard.Model(
      title: "Cradle",
      bookCount: 12,
      bookCovers: [
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"), title: "Book 1"),
        Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"), title: "Book 2"),
      ]
    ),
  ]

  ScrollView {
    SeriesView(series: sampleSeries, displayMode: .card)
      .padding()
  }
}
