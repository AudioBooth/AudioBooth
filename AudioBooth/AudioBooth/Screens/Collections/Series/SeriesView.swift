import SwiftUI

struct SeriesView: View {
  let series: [SeriesCard.Model]
  var hasMorePages: Bool = false
  var onLoadMore: (() -> Void)?

  @Environment(\.itemDisplayMode) private var displayMode

  var body: some View {
    Group {
      switch displayMode {
      case .row:
        LazyVStack(spacing: 12) {
          seriesItems
        }
      case .card:
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 100), spacing: 20)],
          spacing: 20
        ) {
          seriesItems
        }
      }
    }
  }

  @ViewBuilder
  private var seriesItems: some View {
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
}

#Preview("SeriesView - Empty") {
  SeriesView(series: [])
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
    SeriesView(series: sampleSeries)
      .padding()
  }
  .environment(\.itemDisplayMode, .row)
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
    SeriesView(series: sampleSeries)
      .padding()
  }
  .environment(\.itemDisplayMode, .card)
}
