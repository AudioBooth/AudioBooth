import Combine
import SwiftUI

struct SeriesPage: View {
  @ObservedObject var model: Model

  var body: some View {
    content
  }

  var content: some View {
    Group {
      if !model.search.searchText.isEmpty {
        SearchView(model: model.search)
      } else {
        if model.isLoading && model.series.isEmpty {
          ProgressView("Loading series...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.series.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Series Found",
            systemImage: "books.vertical",
            description: Text("Your library appears to have no series or no library is selected.")
          )
        } else {
          seriesContent
        }
      }
    }
    .refreshable {
      await model.refresh()
    }
    .conditionalSearchable(
      text: $model.search.searchText,
      prompt: "Search books, series, and authors"
    )
    .toolbar {
      if #available(iOS 26.0, *) {
        ToolbarItem(placement: .topBarLeading) {
          Color.clear
        }
        .sharedBackgroundVisibility(.hidden)
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle(
            isOn: Binding(
              get: { model.displayMode == .card },
              set: { isOn in
                if isOn && model.displayMode != .card {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("Grid View", systemImage: "square.grid.2x2")
          }

          Toggle(
            isOn: Binding(
              get: { model.displayMode == .row },
              set: { isOn in
                if isOn && model.displayMode != .row {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("List View", systemImage: "rectangle.grid.1x3")
          }
        } label: {
          Image(systemName: "ellipsis")
        }
        .tint(.primary)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  var seriesContent: some View {
    ScrollView {
      SeriesView(
        series: model.series,
        displayMode: model.displayMode,
        hasMorePages: model.hasMorePages,
        onLoadMore: model.loadNextPageIfNeeded
      )
      .padding(.horizontal)
    }
  }
}

extension SeriesPage {
  @Observable class Model: ObservableObject {
    var isLoading: Bool
    var hasMorePages: Bool
    var displayMode: SeriesCard.DisplayMode

    var series: [SeriesCard.Model]
    var search: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}

    init(
      isLoading: Bool = false,
      hasMorePages: Bool = false,
      displayMode: SeriesCard.DisplayMode = .row,
      series: [SeriesCard.Model] = []
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.displayMode = displayMode
      self.series = series
    }
  }
}

extension SeriesPage.Model {
  static var mock: SeriesPage.Model {
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
    ]

    return SeriesPage.Model(series: sampleSeries)
  }
}

#Preview("SeriesPage - Loading") {
  SeriesPage(model: .init(isLoading: true))
}

#Preview("SeriesPage - Empty") {
  SeriesPage(model: .init())
}

#Preview("SeriesPage - With Series") {
  SeriesPage(model: .mock)
}
