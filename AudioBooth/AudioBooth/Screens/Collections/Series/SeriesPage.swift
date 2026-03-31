import API
import Combine
import SwiftUI

struct SeriesPage: View {
  @ObservedObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

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
              get: { preferences.libraryDisplayMode == .card },
              set: { isOn in
                if isOn && preferences.libraryDisplayMode != .card {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("Grid View", systemImage: "square.grid.2x2")
          }

          Toggle(
            isOn: Binding(
              get: { preferences.libraryDisplayMode == .row },
              set: { isOn in
                if isOn && preferences.libraryDisplayMode != .row {
                  model.onDisplayModeTapped()
                }
              }
            )
          ) {
            Label("List View", systemImage: "rectangle.grid.1x3")
          }

          Divider()

          Menu("Sort By") {
            ForEach(model.sortOptions, id: \.self) { sortBy in
              if model.currentSort == sortBy {
                Button(
                  sortBy.displayTitle,
                  systemImage: model.ascending ? "chevron.up" : "chevron.down",
                  action: { model.onSortOptionTapped(sortBy) }
                )
              } else {
                Button(sortBy.displayTitle, action: { model.onSortOptionTapped(sortBy) })
              }
            }
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
        hasMorePages: model.hasMorePages,
        onLoadMore: model.loadNextPageIfNeeded
      )
      .padding(.horizontal)
    }
    .environment(\.itemDisplayMode, preferences.libraryDisplayMode)
  }
}

extension SeriesPage {
  @Observable class Model: ObservableObject {
    var isLoading: Bool
    var hasMorePages: Bool

    var series: [SeriesCard.Model]
    var search: SearchView.Model = SearchView.Model()

    var sortOptions: [SeriesService.SortBy]
    var currentSort: SeriesService.SortBy
    var ascending: Bool

    func onAppear() {}
    func refresh() async {}
    func loadNextPageIfNeeded() {}
    func onDisplayModeTapped() {}
    func onSortOptionTapped(_ sortBy: SeriesService.SortBy) {}

    init(
      isLoading: Bool = false,
      hasMorePages: Bool = false,
      series: [SeriesCard.Model] = [],
      sortOptions: [SeriesService.SortBy] = SeriesService.SortBy.allCases,
      currentSort: SeriesService.SortBy = .name,
      ascending: Bool = true
    ) {
      self.isLoading = isLoading
      self.hasMorePages = hasMorePages
      self.series = series
      self.sortOptions = sortOptions
      self.currentSort = currentSort
      self.ascending = ascending
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
