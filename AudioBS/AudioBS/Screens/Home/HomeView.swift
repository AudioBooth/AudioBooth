import Audiobookshelf
import SwiftData
import SwiftUI

struct HomeView: View {
  @StateModel var model: Model
  @State private var showingDeleteConfirmation = false
  @State private var showingSettings = false
  @AppStorage("audiobookshelf_selected_library") private var libraryData: Data?

  init(model: Model? = nil) {
    if let model {
      self._model = StateModel(wrappedValue: model)
    } else {
      self._model = StateModel(mock: .mock, default: HomeViewModel())
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        if !model.recents.isEmpty {
          recentsContent
        }

        if model.isLoading && model.sections.isEmpty {
          ProgressView("Loading...")
            .frame(maxWidth: .infinity, maxHeight: 200)
        } else if model.sections.isEmpty && !model.isLoading {
          if model.recents.isEmpty {
            emptyState
          } else {
            emptyPersonalizedState
          }
        } else {
          personalizedContent
        }
      }
    }
    .navigationTitle(model.title)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showingSettings = true
        } label: {
          Image(systemName: "gear")
        }
      }
    }
    .sheet(isPresented: $showingSettings) {
      NavigationView {
        SettingsView()
      }
    }
    .onAppear {
      if libraryData == nil {
        showingSettings = true
      }
      model.onAppear()
    }
    .onChange(of: libraryData) { _, _ in
      Task {
        await model.refresh()
      }
    }
    .refreshable {
      await model.refresh()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "headphones")
        .font(.system(size: 60))
        .foregroundColor(.gray.opacity(0.6))

      Text("No Content Available")
        .font(.title2)
        .fontWeight(.medium)
        .foregroundColor(.primary)

      Text("Your personalized content will appear here")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyPersonalizedState: some View {
    VStack(spacing: 16) {
      Text("No additional content available")
        .font(.title3)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .padding(.top, 32)

      Spacer()
    }
    .frame(maxWidth: .infinity, minHeight: 100)
  }

  private var recentsContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Continue Listening")
        .font(.title2)
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 0) {
        ForEach(model.recents, id: \.id) { item in
          RecentRow(model: item)

          if item.id != model.recents.last?.id {
            Divider()
              .padding(.leading, 84)
          }
        }
      }
      .background(Color(.systemGray6))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding(.horizontal)
  }

  private var personalizedContent: some View {
    ForEach(model.sections, id: \.title) { section in
      VStack(alignment: .leading, spacing: 12) {
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)

        switch section.items {
        case .books(let items):
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
              ForEach(items, id: \.id) { book in
                BookCard(model: book)
                  .frame(width: 140)
              }
            }
            .padding(.horizontal)
          }

        case .series(let items):
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
              ForEach(items, id: \.id) { series in
                SeriesCard(model: series, titleFont: .footnote)
                  .frame(width: 280)
              }
            }
            .padding(.horizontal)
          }

        case .authors(let items):
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
              ForEach(items, id: \.id) { author in
                AuthorCard(model: author)
                  .frame(width: 100)
              }
            }
            .padding(.horizontal)
          }
        }
      }
    }
  }
}

extension HomeView {
  @Observable class Model {
    var isLoading: Bool
    var isRoot: Bool
    var title: String

    var recents: [RecentRow.Model]

    struct Section {
      let title: String

      enum Items {
        case books([BookCard.Model])
        case series([SeriesCard.Model])
        case authors([AuthorCard.Model])
      }
      let items: Items
    }
    var sections: [Section]

    @MainActor func onAppear() {}
    @MainActor func refresh() async {}

    init(
      isLoading: Bool = false,
      isRoot: Bool = true,
      title: String = "Home",
      recents: [RecentRow.Model] = [],
      sections: [Section] = []
    ) {
      self.isLoading = isLoading
      self.isRoot = isRoot
      self.title = title
      self.recents = recents
      self.sections = sections
    }
  }
}

extension HomeView.Model {
  static var mock: HomeView.Model {
    let sampleRecentItems: [RecentRow.Model] = [
      RecentRow.Model(
        title: "The Lord of the Rings",
        author: "J.R.R. Tolkien",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        progress: 0.45,
        lastPlayed: Date().addingTimeInterval(-3600)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),
      RecentRow.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayed: Date().addingTimeInterval(-7200)
      ),

    ]

    return HomeView.Model(recents: sampleRecentItems)
  }
}

#Preview("HomeView - Loading") {
  HomeView(model: .init(isLoading: true))
}

#Preview("HomeView - Empty") {
  HomeView(model: .init())
}

#Preview("HomeView - With Recent Items") {
  HomeView(model: .mock)
}
