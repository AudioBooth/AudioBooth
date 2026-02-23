import API
import Combine
import NukeUI
import RichText
import SwiftUI

struct PodcastDetailsView: View {
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  @StateObject var model: Model

  @State private var isDescriptionExpanded = false
  @State private var isShowingFullScreenCover = false
  @State private var activePlaylistModel: CollectionSelectorSheet.Model?

  private enum CoordinateSpaces {
    case scrollView
  }

  var body: some View {
    Group {
      if verticalSizeClass == .compact {
        landscapeLayout
      } else {
        portraitLayout
      }
    }
    .fullScreenCover(isPresented: $isShowingFullScreenCover) {
      if let coverURL = model.coverURL {
        FullScreenCoverView(coverURL: coverURL)
      }
    }
    .overlay {
      if model.isLoading {
        ProgressView("Loading podcast details...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.background)
      } else if let error = model.error {
        ContentUnavailableView {
          Label("Unable to Load Podcast", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again") {
            model.onAppear()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
      }
    }
    .sheet(
      isPresented: Binding(
        get: { activePlaylistModel != nil },
        set: { if !$0 { activePlaylistModel = nil } }
      )
    ) {
      if let sheetModel = activePlaylistModel {
        CollectionSelectorSheet(model: sheetModel)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private func scrollToEpisode(id: String?, proxy: ScrollViewProxy) {
    guard let id else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      withAnimation {
        proxy.scrollTo(id, anchor: .center)
      }
      try? await Task.sleep(for: .milliseconds(400))
      withAnimation { model.highlightedEpisodeID = id }
      model.scrollToEpisodeID = nil
    }
  }

  private var portraitLayout: some View {
    GeometryReader { proxy in
      ScrollViewReader { scrollProxy in
        ScrollView {
          VStack(spacing: 0) {
            cover(offset: proxy.safeAreaInsets.top)
              .frame(height: 266 + proxy.safeAreaInsets.top)

            contentSections
              .padding(.vertical)
              .background()
          }
          .padding(.vertical)
        }
        .coordinateSpace(name: CoordinateSpaces.scrollView)
        .ignoresSafeArea(edges: .top)
        .onChange(of: model.scrollToEpisodeID) { _, id in
          scrollToEpisode(id: id, proxy: scrollProxy)
        }
      }
    }
  }

  private var landscapeLayout: some View {
    HStack(spacing: 0) {
      simpleCover
        .frame(width: 300)

      ScrollViewReader { scrollProxy in
        ScrollView {
          contentSections
            .padding(.vertical)
        }
        .background(.background)
        .onChange(of: model.scrollToEpisodeID) { _, id in
          scrollToEpisode(id: id, proxy: scrollProxy)
        }
      }
    }
  }

  private var contentSections: some View {
    VStack(spacing: 16) {
      VStack(spacing: 16) {
        title

        metadataSection

        if let description = model.description {
          descriptionSection(description)
        }
        if let genres = model.genres, !genres.isEmpty {
          genresSection(genres)
        }
        if let tags = model.tags, !tags.isEmpty {
          tagsSection(tags)
        }
      }
      .padding(.horizontal)

      episodesSection
    }
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(model.title)
          .font(.title)
          .fontWeight(.bold)

        if model.isExplicit {
          Image(systemName: "e.square.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let author = model.author {
        Text(author)
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var metadataSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Metadata")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        if let language = model.language {
          HStack {
            Image(systemName: "globe")
              .accessibilityHidden(true)
            Text("**Language:** \(language)")
          }
          .font(.subheadline)
        }

        HStack {
          Image(systemName: "mic")
            .accessibilityHidden(true)
          Text("**Episodes:** \(model.episodeCount)")
        }
        .font(.subheadline)

        if let podcastType = model.podcastType {
          HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
              .accessibilityHidden(true)
            Text("**Type:** \(podcastType.capitalized)")
          }
          .font(.subheadline)
        }

        if let durationText = model.durationText {
          HStack {
            Image(systemName: "clock")
              .accessibilityHidden(true)
            Text("**Duration:** \(durationText)")
          }
          .font(.subheadline)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func cover(offset: CGFloat) -> some View {
    ParallaxHeader(coordinateSpace: CoordinateSpaces.scrollView) {
      ZStack(alignment: .center) {
        LazyImage(url: model.coverURL) { state in
          state.image?
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: 5)
            .opacity(0.3)
        }

        Cover(
          model: Cover.Model(
            url: model.coverURL,
            title: model.title,
            author: model.author
          ),
          style: .plain
        )
        .shadow(radius: 4)
        .frame(width: 250, height: 250)
        .offset(y: offset / 2 - 8)
        .onTapGesture {
          guard model.coverURL != nil else { return }
          isShowingFullScreenCover = true
        }
      }
    }
  }

  private var simpleCover: some View {
    VStack {
      Cover(
        model: Cover.Model(
          url: model.coverURL,
          title: model.title,
          author: model.author
        ),
        style: .plain
      )
      .frame(width: 200, height: 200)
      .shadow(radius: 4)
      .padding()
      .onTapGesture {
        guard model.coverURL != nil else { return }
        isShowingFullScreenCover = true
      }
    }
    .frame(maxHeight: .infinity)
    .background {
      LazyImage(url: model.coverURL) { state in
        state.image?
          .resizable()
          .scaledToFill()
          .blur(radius: 5)
          .opacity(0.3)
      }
    }
    .ignoresSafeArea(edges: .vertical)
  }

  private func genresSection(_ genres: [String]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Genres")
        .font(.headline)

      FlowLayout(spacing: 4) {
        ForEach(genres, id: \.self) { genre in
          NavigationLink(value: NavigationDestination.genre(name: genre)) {
            Chip(
              title: genre,
              icon: "theatermasks.fill",
              color: .gray
            )
          }
        }
      }
    }
  }

  private func tagsSection(_ tags: [String]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tags")
        .font(.headline)

      FlowLayout(spacing: 4) {
        ForEach(tags, id: \.self) { tag in
          NavigationLink(value: NavigationDestination.tag(name: tag)) {
            Chip(
              title: tag,
              icon: "tag.fill",
              color: .gray
            )
          }
        }
      }
    }
  }

  private func descriptionSection(_ description: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Description")
        .font(.headline)

      ZStack(alignment: .bottom) {
        RichText(
          html: description,
          configuration: Configuration(
            customCSS: "body { font: -apple-system-subheadline; }"
          )
        )
        .frame(maxHeight: isDescriptionExpanded ? nil : 180, alignment: .top)
        .contentShape(Rectangle())
        .clipped()
        .allowsHitTesting(false)

        if !isDescriptionExpanded {
          LinearGradient(
            colors: [.clear, Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 60)
          .accessibilityHidden(true)
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.25)) {
        isDescriptionExpanded.toggle()
      }
    }
    .textSelection(.enabled)
  }

  // MARK: - Episodes

  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(model.episodesTitle)
          .font(.headline)
        Spacer()
        Button {
          model.onPlayAllEpisodes()
        } label: {
          Label("Play", systemImage: "play.fill")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.filteredEpisodes.isEmpty)
      }
      .padding(.horizontal)

      HStack {
        Picker("Filter", selection: $model.selectedFilter) {
          ForEach(Model.EpisodeFilter.allCases, id: \.self) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .pickerStyle(.menu)

        Spacer()

        Menu {
          ForEach(Model.EpisodeSort.allCases, id: \.self) { sort in
            Button {
              model.onSortOptionTapped(sort)
            } label: {
              if model.selectedSort == sort {
                Label(
                  sort.title,
                  systemImage: model.ascending ? "chevron.up" : "chevron.down"
                )
              } else {
                Text(sort.title)
              }
            }
          }
        } label: {
          Label(
            model.selectedSort.title,
            systemImage: model.ascending ? "chevron.up" : "chevron.down"
          )
          .font(.subheadline)
        }
      }
      .padding(.horizontal)

      TextField("Search episodes", text: $model.searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)

      VStack(spacing: 0) {
        ForEach(model.filteredEpisodes) { episode in
          NavigationLink {
            PodcastEpisodeDetailView(
              model: PodcastEpisodeDetailViewModel(
                podcastID: model.podcastID,
                podcastTitle: model.title,
                podcastAuthor: model.author,
                coverURL: model.coverURL,
                episode: episode
              )
            )
          } label: {
            episodeRow(episode)
              .padding(.horizontal)
          }
          .buttonStyle(.plain)
          .contextMenu {
            if let contextMenu = episode.contextMenu {
              PodcastEpisodeContextMenu(model: contextMenu)
            }
          }
          .onChange(of: episode.contextMenu?.showingPlaylistSheet) { _, showing in
            guard showing == true else { return }
            episode.contextMenu?.showingPlaylistSheet = false
            activePlaylistModel = CollectionSelectorSheetModel(
              bookID: model.podcastID,
              episodeID: episode.id,
              mode: .playlists
            )
          }
          .background(
            episode.id == model.highlightedEpisodeID
              ? Color.accentColor.opacity(0.15)
              : Color.clear
          )
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .id(episode.id)
          Divider()
        }
      }
    }
  }

  private func episodeRow(_ episode: Model.Episode) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          if let season = episode.season, !season.isEmpty, let ep = episode.episode, !ep.isEmpty {
            Text("S\(season)E\(ep)")
              .font(.caption2)
              .fontWeight(.medium)
              .foregroundStyle(.secondary)
          } else if let ep = episode.episode, !ep.isEmpty {
            Text("E\(ep)")
              .font(.caption2)
              .fontWeight(.medium)
              .foregroundStyle(.secondary)
          }

          Text(episode.title)
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }

        if let publishedAt = episode.publishedAt {
          Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        episodePlayButton(episode)

        if episode.progress > 0 {
          ProgressView(value: min(episode.progress, 1.0))
            .tint(.accentColor)
        }
      }

      Spacer(minLength: 0)

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  private func episodePlayButton(_ episode: Model.Episode) -> some View {
    let isCurrentEpisode = episode.id == model.currentlyPlayingEpisodeID
    let isCurrentlyPlaying = isCurrentEpisode && model.isPlaying

    return Button {
      model.onPlayEpisode(episode)
    } label: {
      Label {
        Text(episodePlayButtonText(for: episode, isCurrentlyPlaying: isCurrentlyPlaying))
      } icon: {
        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
      }
      .font(.caption)
      .fontWeight(.medium)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .foregroundStyle(isCurrentlyPlaying ? .white : Color.accentColor)
      .background(isCurrentlyPlaying ? Color.accentColor : Color.accentColor.opacity(0.15))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func episodePlayButtonText(
    for episode: Model.Episode,
    isCurrentlyPlaying: Bool
  ) -> String {
    if isCurrentlyPlaying {
      return "Pause"
    }
    if episode.isCompleted {
      return "Played"
    }
    guard let duration = episode.duration, duration > 0 else {
      return "Play"
    }
    let seconds: Double
    if episode.progress > 0 {
      seconds = duration * (1 - episode.progress)
    } else {
      seconds = duration
    }
    let text = Duration.seconds(seconds).formatted(
      .units(allowed: [.hours, .minutes], width: .narrow)
    )
    if episode.progress > 0 {
      return "\(text) left"
    }
    return text
  }

}

// MARK: - Model

extension PodcastDetailsView {
  @Observable
  class Model: ObservableObject {
    let podcastID: String
    var title: String
    var author: String?
    var coverURL: URL?
    var description: String?
    var genres: [String]?
    var tags: [String]?
    var isLoading: Bool
    var error: String?
    var isExplicit: Bool
    var language: String?
    var podcastType: String?
    var durationText: String?
    var episodeCount: Int

    var episodes: [Episode]
    var searchText: String
    var selectedFilter: EpisodeFilter
    var selectedSort: EpisodeSort
    var ascending: Bool

    var currentlyPlayingEpisodeID: String?
    var isPlaying: Bool

    var scrollToEpisodeID: String?
    var highlightedEpisodeID: String?

    var episodesTitle: String {
      let filtered = filteredEpisodes.count
      let total = episodes.count
      if searchText.isEmpty && selectedFilter == .all {
        return "\(total) Episodes"
      } else {
        return "\(filtered)/\(total) Episodes"
      }
    }

    var filteredEpisodes: [Episode] {
      var result = episodes

      if !searchText.isEmpty {
        let query = searchText.lowercased()
        result = result.filter {
          $0.title.lowercased().contains(query)
            || ($0.description?.lowercased().contains(query) ?? false)
        }
      }

      switch selectedFilter {
      case .all:
        break
      case .incomplete:
        result = result.filter { !$0.isCompleted }
      case .complete:
        result = result.filter { $0.isCompleted }
      case .inProgress:
        result = result.filter { $0.progress > 0 && !$0.isCompleted }
      }

      switch selectedSort {
      case .pubDate:
        result.sort {
          if ascending {
            return ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast)
          } else {
            return ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
          }
        }
      case .title:
        result.sort {
          let order = $0.title.localizedCaseInsensitiveCompare($1.title)
          return ascending ? order == .orderedAscending : order == .orderedDescending
        }
      case .season:
        result.sort {
          let s0 = Int($0.season ?? "") ?? 0
          let s1 = Int($1.season ?? "") ?? 0
          if s0 != s1 { return ascending ? s0 < s1 : s0 > s1 }
          let e0 = Int($0.episode ?? "") ?? 0
          let e1 = Int($1.episode ?? "") ?? 0
          return ascending ? e0 < e1 : e0 > e1
        }
      case .episode:
        result.sort {
          let e0 = Int($0.episode ?? "") ?? 0
          let e1 = Int($1.episode ?? "") ?? 0
          return ascending ? e0 < e1 : e0 > e1
        }
      }

      return result
    }

    func onAppear() {}
    func onPlayEpisode(_ episode: Episode) {}
    func onPlayAllEpisodes() {}
    func onSortOptionTapped(_ sort: EpisodeSort) {
      if selectedSort == sort {
        ascending.toggle()
      } else {
        selectedSort = sort
        ascending = false
      }
    }

    init(
      podcastID: String,
      title: String = "",
      author: String? = nil,
      coverURL: URL? = nil,
      description: String? = nil,
      genres: [String]? = nil,
      tags: [String]? = nil,
      isLoading: Bool = true,
      error: String? = nil,
      isExplicit: Bool = false,
      language: String? = nil,
      podcastType: String? = nil,
      durationText: String? = nil,
      episodeCount: Int = 0,
      episodes: [Episode] = [],
      searchText: String = "",
      selectedFilter: EpisodeFilter = .all,
      selectedSort: EpisodeSort = .pubDate,
      ascending: Bool = false,
      currentlyPlayingEpisodeID: String? = nil,
      isPlaying: Bool = false
    ) {
      self.podcastID = podcastID
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.description = description
      self.genres = genres
      self.tags = tags
      self.isLoading = isLoading
      self.error = error
      self.isExplicit = isExplicit
      self.language = language
      self.podcastType = podcastType
      self.durationText = durationText
      self.episodeCount = episodeCount
      self.episodes = episodes
      self.searchText = searchText
      self.selectedFilter = selectedFilter
      self.selectedSort = selectedSort
      self.ascending = ascending
      self.currentlyPlayingEpisodeID = currentlyPlayingEpisodeID
      self.isPlaying = isPlaying
    }
  }
}

// MARK: - Episode

extension PodcastDetailsView.Model {
  struct Episode: Identifiable {
    let id: String
    let title: String
    let season: String?
    let episode: String?
    let publishedAt: Date?
    let duration: Double?
    let size: Int64?
    let description: String?
    let isCompleted: Bool
    let progress: Double
    let chapters: [Chapter]
    var downloadState: DownloadManager.DownloadState
    var contextMenu: PodcastEpisodeContextMenu.Model?
    var apiEpisode: PodcastEpisode?

    var durationText: String? {
      guard let duration, duration > 0 else { return nil }
      return Duration.seconds(duration).formatted(
        .units(
          allowed: [.hours, .minutes],
          width: .narrow
        )
      )
    }
  }

  struct Chapter: Identifiable {
    let id: Int
    let start: Double
    let end: Double
    let title: String

    var durationText: String {
      Duration.seconds(end - start).formatted(
        .units(
          allowed: [.hours, .minutes, .seconds],
          width: .narrow
        )
      )
    }

    var startText: String {
      Duration.seconds(start).formatted(
        .units(
          allowed: [.hours, .minutes, .seconds],
          width: .narrow
        )
      )
    }
  }
}

// MARK: - Enums

extension PodcastDetailsView.Model {
  enum EpisodeFilter: CaseIterable {
    case all, incomplete, complete, inProgress

    var title: String {
      switch self {
      case .all: "All"
      case .incomplete: "Incomplete"
      case .complete: "Complete"
      case .inProgress: "In Progress"
      }
    }
  }

  enum EpisodeSort: CaseIterable {
    case pubDate, title, season, episode

    var title: String {
      switch self {
      case .pubDate: "Pub Date"
      case .title: "Title"
      case .season: "Season"
      case .episode: "Episode"
      }
    }
  }
}

// MARK: - Mock

extension PodcastDetailsView.Model {
  static var mock: PodcastDetailsView.Model {
    PodcastDetailsView.Model(
      podcastID: "mock-podcast",
      title: "The Daily",
      author: "The New York Times",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
      description:
        "This is what the news should sound like. The biggest stories of our time, told by the best journalists in the world.",
      genres: ["News", "Daily News"],
      tags: ["news", "daily"],
      isLoading: false,
      isExplicit: false,
      language: "English",
      podcastType: "episodic",
      durationText: "48hr 30min",
      episodeCount: 3,
      episodes: [
        Episode(
          id: "ep1",
          title: "The Sunday Read: 'The Untold Story'",
          season: "1",
          episode: "1",
          publishedAt: Date(),
          duration: 1800,
          size: nil,
          description: "A deep dive into an untold story.",
          isCompleted: true,
          progress: 1.0,
          chapters: [
            Chapter(id: 0, start: 0, end: 600, title: "Introduction"),
            Chapter(id: 1, start: 600, end: 1200, title: "The Discovery"),
            Chapter(id: 2, start: 1200, end: 1800, title: "Conclusion"),
          ],
          downloadState: .notDownloaded
        ),
        Episode(
          id: "ep2",
          title: "Breaking Down the Headlines",
          season: "1",
          episode: "2",
          publishedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
          duration: 2400,
          size: nil,
          description: "Today's top headlines explained.",
          isCompleted: false,
          progress: 0.45,
          chapters: [],
          downloadState: .downloading(progress: 0.45)
        ),
        Episode(
          id: "ep3",
          title: "A New Chapter",
          season: "1",
          episode: "3",
          publishedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
          duration: 3600,
          size: nil,
          description: nil,
          isCompleted: false,
          progress: 0,
          chapters: [],
          downloadState: .downloaded
        ),
      ]
    )
  }
}

#Preview {
  NavigationStack {
    PodcastDetailsView(model: .mock)
  }
}
