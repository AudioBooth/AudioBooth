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

  var connectionStatusLabel: String {
    switch authentication.server?.status {
    case .connected:
      return String(localized: "Connected")
    case .connectionError:
      return String(localized: "Connection error")
    case .authenticationError:
      return String(localized: "Authentication error")
    case .none:
      return String(localized: "Disconnected")
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
          case .author(let id, let name):
            AuthorDetailsView(model: AuthorDetailsViewModel(authorID: id, name: name))
          case .series, .narrator, .genre, .tag, .authorLibrary:
            LibraryPage(model: LibraryPageModel(destination: destination))
          case .playlist(let id):
            CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .playlists))
          case .collection(let id):
            CollectionDetailPage(model: CollectionDetailPageModel(collectionID: id, mode: .collections))
          case .podcast(let id, let episodeID):
            PodcastDetailsView(model: PodcastDetailsViewModel(podcastID: id, episodeID: episodeID))
          case .stats:
            StatsPageView(model: StatsPageViewModel())
          }
        }
    }
  }

  var content: some View {
    ScrollView {
      VStack(spacing: 24) {
        if let error = model.error {
          Text(error)
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.red.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
              RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.5), lineWidth: 2)
            }
            .padding(.horizontal)
        }

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
    .navigationTitle("Home")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          showingServerPicker = true
        } label: {
          HStack(spacing: 4) {
            Text("●")
              .foregroundStyle(connectionStatusColor)

            Text(libraries.current?.name ?? "Server")
              .bold()
          }
          .frame(maxWidth: 250)
        }
        .accessibilityLabel("Server: \(libraries.current?.name ?? "Server"), \(connectionStatusLabel)")
        .tint(.primary)
      }

      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showingSettings = true
        } label: {
          Image(systemName: "gear")
        }
        .tint(.primary)
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
      if !authentication.isAuthenticated || libraries.current == nil {
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

      case .playlist(let id, let items):
        NavigationLink(value: NavigationDestination.playlist(id: id)) {
          HStack {
            Text(section.title)
              .font(.title2)
              .fontWeight(.semibold)
              .foregroundColor(.primary)
              .accessibilityAddTraits(.isHeader)

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
          HStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.id) { book in
              BookCard(model: book)
                .frame(width: 120)
            }
          }
          .padding(.horizontal)
        }

      case .continueBooks(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .accessibilityAddTraits(.isHeader)

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 16) {
            ForEach(items, id: \.id) { item in
              BookCard(model: item)
                .frame(width: preferences.continueSectionSize.value)
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
          .accessibilityAddTraits(.isHeader)

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
          .accessibilityAddTraits(.isHeader)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 16) {
            ForEach(items) { series in
              SeriesCard(model: series, titleFont: .footnote)
                .frame(width: preferences.seriesDisplayMode == .card ? 120 : 240)
            }
          }
          .padding(.horizontal)
        }
        .environment(\.seriesCardDisplayMode, preferences.seriesDisplayMode)

      case .authors(let items):
        Text(section.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal)
          .accessibilityAddTraits(.isHeader)

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

    var error: String?

    struct Section {
      let id: String
      let title: String

      enum Items {
        case stats
        case continueBooks([BookCard.Model])
        case playlist(id: String, items: [BookCard.Model])
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
      error: String? = nil,
      sections: [Section] = []
    ) {
      self.isLoading = isLoading
      self.isRoot = isRoot
      self.error = error
      self.sections = sections
    }
  }
}

extension HomePage.Model {
  static var mock: HomePage.Model {
    let books: [BookCard.Model] = [
      BookCard.Model(
        title: "The Lord of the Rings",
        details: "8hr 32min remaining",
        cover: Cover.Model(
          url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
          progress: 0.45
        )
      ),
      BookCard.Model(
        title: "Dune",
        details: "2hr 15min remaining",
        cover: Cover.Model(
          url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
          progress: 0.12
        )
      ),
    ]

    return HomePage.Model(
      error:
        "Some features may be limited on server version 2.20.0. For the best experience, please update your server.",
      sections: [
        Section(
          id: "continue-listening",
          title: "Continue Listening",
          items: .continueBooks(books)
        )
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
