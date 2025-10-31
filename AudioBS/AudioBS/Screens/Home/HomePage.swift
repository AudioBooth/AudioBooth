import API
import Combine
import SwiftData
import SwiftUI

struct HomePage: View {
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  @StateObject var model: Model
  @State private var showingSettings = false

  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack {
      content
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .book(let id):
            BookDetailsView(model: BookDetailsViewModel(bookID: id))
          case .series, .author, .narrator, .genre, .tag, .offline:
            LibraryPage(model: LibraryPageModel(destination: destination))
          }
        }
    }
  }

  var content: some View {
    ScrollView {
      VStack(spacing: 24) {
        if model.showStats {
          ListeningStatsCard(model: ListeningStatsCardModel())
            .padding(.horizontal)
        }

        if let section = model.continueListening {
          sectionContent(section)
        }

        if let section = model.offline {
          sectionContent(section, isOffline: true)
        }

        if model.isLoading && model.others.isEmpty {
          ProgressView("Loading...")
            .frame(maxWidth: .infinity, maxHeight: 200)
        } else if model.others.isEmpty && !model.isLoading {
          if model.continueListening == nil && model.offline == nil {
            emptyState
          } else {
            emptyPersonalizedState
          }
        } else {
          ForEach(model.others, id: \.title) { section in
            sectionContent(section)
          }
        }
      }
      .padding(.bottom)
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
        SettingsView(model: SettingsViewModel())
      }
    }
    .onAppear {
      if libraries.current == nil {
        showingSettings = true
      }
      model.onAppear()
    }
    .onChange(of: libraries.current) { _, new in
      model.onReset(new != nil)
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

  @ViewBuilder
  private func sectionContent(_ section: HomePage.Model.Section, isOffline: Bool = false)
    -> some View
  {
    VStack(alignment: .leading, spacing: 12) {
      if isOffline {
        NavigationLink(value: NavigationDestination.offline) {
          HStack {
            Text(section.title)
              .font(.title2)
              .fontWeight(.semibold)
              .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
              .font(.body)
              .foregroundColor(.secondary)
          }
          .padding(.horizontal)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
      }

      switch section.items {
      case .continueListening(let items):
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 16) {
            ForEach(items) { item in
              ContinueListeningCard(model: item)
            }
          }
          .padding(.horizontal)
        }

      case .books(let items):
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 16) {
            ForEach(items, id: \.id) { book in
              BookCard(model: book)
                .frame(width: 120)
            }
          }
          .padding(.horizontal)
        }

      case .series(let items):
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 16) {
            ForEach(items, id: \.id) { series in
              SeriesCard(model: series, titleFont: .footnote)
                .frame(width: 240)
            }
          }
          .padding(.horizontal)
        }

      case .authors(let items):
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 16) {
            ForEach(items, id: \.id) { author in
              AuthorCard(model: author)
                .frame(width: 80)
            }
          }
          .padding(.horizontal)
        }
      }
    }
  }
}

extension HomePage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var isRoot: Bool
    var title: String

    @ObservationIgnored
    @AppStorage("showListeningStats") var showListeningStats: Bool = false

    var showStats: Bool {
      showListeningStats && Audiobookshelf.shared.authentication.isAuthenticated
    }

    struct Section {
      let title: String

      enum Items {
        case continueListening([ContinueListeningCard.Model])
        case books([BookCard.Model])
        case series([SeriesCard.Model])
        case authors([AuthorCard.Model])
      }
      let items: Items

      init(title: String, items: Items) {
        self.title = title
        self.items = items
      }
    }

    var continueListening: Section?
    var offline: Section?
    var others: [Section]

    func onAppear() {}
    func refresh() async {}
    func onReset(_ shouldRefresh: Bool) {}

    init(
      isLoading: Bool = false,
      isRoot: Bool = true,
      title: String = "Home",
      continueListening: Section? = nil,
      offline: Section? = nil,
      others: [Section] = []
    ) {
      self.isLoading = isLoading
      self.isRoot = isRoot
      self.title = title
      self.continueListening = continueListening
      self.offline = offline
      self.others = others
    }
  }
}

extension HomePage.Model {
  static var mock: HomePage.Model {
    let books: [ContinueListeningCard.Model] = [
      ContinueListeningCard.Model(
        title: "The Lord of the Rings",
        author: "J.R.R. Tolkien",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        progress: 0.45,
        lastPlayedAt: Date().addingTimeInterval(-3600)
      ),
      ContinueListeningCard.Model(
        title: "Dune",
        author: "Frank Herbert",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        progress: 0.12,
        lastPlayedAt: Date().addingTimeInterval(-7200)
      ),
    ]

    return HomePage.Model(
      continueListening: Section(title: "Continue Listening", items: .continueListening(books))
    )
  }
}

#Preview("HomePage - Loading") {
  HomePage(model: .init(isLoading: true))
}

#Preview("HomePage - Empty") {
  HomePage(model: .init())
}

#Preview("HomePage - With Continue Listening") {
  HomePage(model: .mock)
}
