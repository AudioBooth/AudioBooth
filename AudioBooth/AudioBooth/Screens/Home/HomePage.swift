import API
import Combine
import SwiftData
import SwiftUI

struct HomePage: View {
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared

  @StateObject var model: Model
  @State private var showingSettings = false
  @State private var showingServerPicker = false

  @State private var path = NavigationPath()

  var connectionStatusColor: Color {
    switch authentication.server?.status {
    case .connected:
      return .green
    case .connectionError:
      return .orange
    case .authenticationError:
      return .red
    case .none:
      return .gray
    }
  }

  var body: some View {
    NavigationStack {
      content
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .book(let id):
            BookDetailsView(model: BookDetailsViewModel(bookID: id))
          case .offline:
            OfflineListView(model: OfflineListViewModel())
          case .series, .author, .narrator, .genre, .tag:
            LibraryPage(model: LibraryPageModel(destination: destination))
          case .playlist, .collection:
            EmptyView()
          }
        }
    }
  }

  var content: some View {
    ScrollView {
      VStack(spacing: 24) {
        ForEach(model.sections, id: \.id) { section in
          sectionContent(section)
        }

        if model.isLoading && model.sections.isEmpty {
          ProgressView("Loading...")
            .frame(maxWidth: .infinity, maxHeight: 200)
        } else if model.sections.isEmpty && !model.isLoading {
          emptyState
        }
      }
      .padding(.bottom)
    }
    .navigationTitle(model.title)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button {
          showingServerPicker = true
        } label: {
          Text("●")
            .foregroundStyle(connectionStatusColor)

          Text(libraries.current?.name ?? "Server")
            .bold()
        }
      }

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
    .sheet(isPresented: $showingServerPicker) {
      ServerListPage(model: ServerListModel())
    }
    .onAppear {
      if !Audiobookshelf.shared.isAuthenticated {
        showingServerPicker = true
      } else if libraries.current == nil {
        showingServerPicker = true
      }
      model.onAppear()
    }
    .onChange(of: libraries.current) { _, new in
      showingServerPicker = false
      model.onReset(new != nil)
    }
    .onChange(of: preferences.homeSections) { _, _ in
      model.onPreferencesChanged()
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

  @ViewBuilder
  private func sectionContent(_ section: HomePage.Model.Section) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      switch section.items {
      case .stats:
        ListeningStatsCard(model: ListeningStatsCardModel())
          .padding(.horizontal)

      case .offline(let items):
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

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.id) { book in
              BookCard(model: book)
                .frame(width: 120)
            }
          }
          .padding(.horizontal)
        }

      case .continueListening(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 16) {
            ForEach(items) { item in
              ContinueListeningCard(model: item)
            }
          }
          .padding(.horizontal)
        }

      case .books(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.id) { book in
              BookCard(model: book)
                .frame(width: 120)
            }
          }
          .padding(.horizontal)
        }

      case .series(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.id) { series in
              SeriesCard(model: series, titleFont: .footnote)
                .frame(width: 240)
            }
          }
          .padding(.horizontal)
        }

      case .authors(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 16) {
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

    struct Section {
      let id: String
      let title: String

      enum Items {
        case stats
        case continueListening([ContinueListeningCard.Model])
        case offline([BookCard.Model])
        case books([BookCard.Model])
        case series([SeriesCard.Model])
        case authors([AuthorCard.Model])
      }
      let items: Items

      init(id: String, title: String, items: Items) {
        self.id = id
        self.title = title
        self.items = items
      }
    }

    var sections: [Section]

    func onAppear() {}
    func refresh() async {}
    func onReset(_ shouldRefresh: Bool) {}
    func onPreferencesChanged() {}

    init(
      isLoading: Bool = false,
      isRoot: Bool = true,
      title: String = "Home",
      sections: [Section] = []
    ) {
      self.isLoading = isLoading
      self.isRoot = isRoot
      self.title = title
      self.sections = sections
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
      sections: [
        Section(
          id: "continue-listening", title: "Continue Listening", items: .continueListening(books))
      ]
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
