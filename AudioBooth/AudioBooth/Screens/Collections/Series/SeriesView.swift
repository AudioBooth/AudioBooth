import SwiftUI

struct SeriesView: View {
  let series: [SeriesCard.Model]
  var hasMorePages: Bool = false
  var onLoadMore: (() -> Void)?

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 250), spacing: 20)],
      spacing: 20
    ) {
      ForEach(series, id: \.id) { series in
        SeriesCard(model: series)
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

#Preview("SeriesView - Empty") {
  SeriesView(series: [])
}

#Preview("SeriesView - With Series") {
  let sampleSeries: [SeriesCard.Model] = [
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")]
    ),
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")]
    ),
    SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: [
        URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
      ]
    ),
    SeriesCard.Model(
      title: "First Immortal",
      bookCount: 4,
      bookCovers: [URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")]
    ),
  ]

  ScrollView {
    SeriesView(series: sampleSeries)
      .padding()
  }
}
