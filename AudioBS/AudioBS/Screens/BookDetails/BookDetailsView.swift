import API
import Combine
import Models
import SwiftUI

struct BookDetailsView: View {
  @ObservedObject var model: Model
  @Environment(\.verticalSizeClass) private var verticalSizeClass

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
    .overlay {
      if model.isLoading {
        ProgressView("Loading book details...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.background)
      } else if let error = model.error {
        ContentUnavailableView {
          Label("Unable to Load Book", systemImage: "exclamationmark.triangle")
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
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
          Button(action: model.onDownloadTapped) {
            Label(downloadButtonText, systemImage: downloadButtonIcon)
          }

          Button(action: model.onMarkFinishedTapped) {
            Label(markFinishedText, systemImage: markFinishedIcon)
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .imageScale(.large)
        }
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private var portraitLayout: some View {
    ScrollView {
      VStack(spacing: 0) {
        cover

        contentSections
          .padding()
          .background()
      }
      .padding(.vertical)
    }
    .coordinateSpace(name: CoordinateSpaces.scrollView)
    .ignoresSafeArea(edges: .top)
  }

  private var landscapeLayout: some View {
    HStack(spacing: 0) {
      simpleCover
        .frame(width: 300)

      ScrollView {
        contentSections
          .padding()
      }
      .background(.background)
    }
  }

  private var contentSections: some View {
    VStack(spacing: 16) {
      Text(model.title)
        .font(.title)
        .fontWeight(.bold)
        .multilineTextAlignment(.leading)

      actionButtons

      headerSection
      infoSection
      if let description = model.description {
        descriptionSection(description)
      }
      if let genres = model.genres, !genres.isEmpty {
        genresSection(genres)
      }
      if let tags = model.tags, !tags.isEmpty {
        tagsSection(tags)
      }
      if let chapters = model.chapters, !chapters.isEmpty {
        chaptersSection(chapters)
      }
    }
  }

  private var cover: some View {
    ParallaxHeader(coordinateSpace: CoordinateSpaces.scrollView) {
      ZStack(alignment: .bottom) {
        LazyImage(url: model.coverURL) { state in
          state.image?
            .resizable()
            .scaledToFill()
            .blur(radius: 5)
            .opacity(0.3)
        }

        CoverImage(url: model.coverURL)
          .frame(width: 250, height: 250)
          .overlay(alignment: .bottom) {
            if let progress = model.progress, progress > 0 {
              progressBar(progress)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(radius: 4)
          .padding(24)
      }
    }
  }

  private var simpleCover: some View {
    VStack {
      CoverImage(url: model.coverURL)
        .frame(width: 200, height: 200)
        .overlay(alignment: .bottom) {
          if let progress = model.progress, progress > 0 {
            progressBar(progress)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding()
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

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !model.authors.isEmpty || !model.narrators.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Authors & Narrators")
            .font(.headline)

          FlowLayout(spacing: 4) {
            ForEach(model.authors, id: \.id) { author in
              NavigationLink(value: NavigationDestination.author(id: author.id, name: author.name))
              {
                Chip(
                  title: author.name,
                  icon: "person.circle.fill",
                  color: .blue
                )
              }
            }

            ForEach(model.narrators, id: \.self) { narrator in
              NavigationLink(value: NavigationDestination.narrator(name: narrator)) {
                Chip(
                  title: narrator,
                  icon: "person.wave.2.fill",
                  color: .blue
                )
              }
            }
          }
        }
      }

      if !model.series.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Series")
            .font(.headline)

          FlowLayout(spacing: 4) {
            ForEach(model.series, id: \.id) { series in
              NavigationLink(value: NavigationDestination.series(id: series.id, name: series.name))
              {
                Chip(
                  title: series.sequence.isEmpty
                    ? series.name : "\(series.name) #\(series.sequence)",
                  icon: "square.stack.3d.up.fill",
                  color: .orange
                )
              }
            }
          }
        }
      }
    }
    .textSelection(.enabled)
  }

  private var infoSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Metadata")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        if let publisher = model.publisher {
          HStack {
            Image(systemName: "building.2")
            Text("**Publisher:** \(publisher)")
          }
          .font(.subheadline)
        }

        if let publishedYear = model.publishedYear {
          HStack {
            Image(systemName: "calendar")
            Text("**Published:** \(publishedYear)")
          }
          .font(.subheadline)
        }

        if let duration = model.durationText {
          HStack {
            Image(systemName: "clock")
            Text("**Duration:** \(duration)")
          }
          .font(.subheadline)
        }

        if let progress = model.progress, progress > 0 {
          HStack {
            Image(systemName: "chart.bar.fill")
            Text("**Progress:** \(progress.formatted(.percent.precision(.fractionLength(0))))")
          }
          .font(.subheadline)
        }

        if let timeRemaining = model.timeRemaining {
          HStack {
            Image(systemName: "clock.arrow.circlepath")
            Text("**Time remaining:** \(timeRemaining)")
          }
          .font(.subheadline)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var downloadStateView: some View {
    switch model.downloadState {
    case .downloading(let progress):
      HStack {
        Image(systemName: "arrow.down.circle")
        Text("Downloading: \(progress.formatted(.percent.precision(.fractionLength(0))))")
      }
      .font(.subheadline)
      .frame(maxWidth: .infinity, alignment: .leading)
    case .downloaded, .notDownloaded:
      EmptyView()
    }
  }

  private var actionButtons: some View {
    VStack(spacing: 12) {
      Button(action: model.onPlayTapped) {
        HStack {
          Image(systemName: playButtonIcon)
          Text(playButtonText)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background {
          if let progress = model.progress, progress >= 0.01 {
            GeometryReader { geometry in
              ZStack(alignment: .leading) {
                Color.accentColor.opacity(0.6)

                Rectangle()
                  .fill(Color.accentColor)
                  .frame(width: geometry.size.width * progress)
              }
            }
          } else {
            Color.accentColor
          }
        }
        .foregroundColor(.white)
        .cornerRadius(12)
      }

      HStack(spacing: 12) {
        Button(role: downloadButtonRole, action: model.onDownloadTapped) {
          HStack {
            Image(systemName: downloadButtonIcon)
            Text(downloadButtonText)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(8)
          .background(Color.secondary.opacity(0.2))
          .cornerRadius(12)
        }

        Button(action: model.onMarkFinishedTapped) {
          HStack {
            Image(systemName: markFinishedIcon)
            Text(markFinishedText)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(8)
          .background(Color.secondary.opacity(0.2))
          .cornerRadius(12)
        }
      }
      .font(.subheadline)

      downloadStateView
    }
  }

  private var playButtonIcon: String {
    if model.isCurrentlyPlaying {
      return "pause.fill"
    }
    return "play.fill"
  }

  private var playButtonText: String {
    if model.isEbook {
      return "Read"
    }
    if model.isCurrentlyPlaying {
      return "Pause"
    }
    if let progress = model.progress, progress > 0 {
      return "Continue Listening"
    }
    return "Play"
  }

  private var downloadButtonRole: ButtonRole? {
    switch model.downloadState {
    case .downloading: nil
    case .downloaded: .destructive
    case .notDownloaded: nil
    }
  }

  private var downloadButtonIcon: String {
    switch model.downloadState {
    case .downloading:
      return "stop.circle"
    case .downloaded:
      return "trash"
    case .notDownloaded:
      return "arrow.down.circle"
    }
  }

  private var downloadButtonText: String {
    switch model.downloadState {
    case .downloading:
      return "Cancel"
    case .downloaded:
      return "Remove Download"
    case .notDownloaded:
      return "Download"
    }
  }

  private var markFinishedIcon: String {
    if let progress = model.progress, progress >= 1.0 {
      return "checkmark.shield.fill"
    }
    return "checkmark.shield"
  }

  private var markFinishedText: String {
    if let progress = model.progress, progress >= 1.0 {
      return "Mark as Unfinished"
    }
    return "Mark as Finished"
  }

  private func progressBar(_ progress: Double) -> some View {
    GeometryReader { geometry in
      let progressColor: Color = progress >= 1.0 ? .green : .orange

      Rectangle()
        .fill(progressColor)
        .frame(width: geometry.size.width * progress, height: 8)
    }
    .frame(height: 8)
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

  private func chaptersSection(_ chapters: [Chapter]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Chapters")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(chapters, id: \.id) { chapter in
          HStack {
            Text(chapter.title)
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatDuration(chapter.end - chapter.start))
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 4)
        }
      }
      .padding()
      .background(Color.secondary.opacity(0.1))
      .cornerRadius(8)
    }
  }

  private func tracksSection(_ tracks: [Track]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Audio Files")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(tracks.enumerated()), id: \.element.index) { index, track in
          HStack {
            Text(track.title ?? "Track \(index + 1)")
              .font(.subheadline)
            Spacer()
            Text(formatDuration(track.duration))
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 4)
        }
      }
      .padding()
      .background(Color.secondary.opacity(0.1))
      .cornerRadius(8)
    }
  }

  private func formatDuration(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(
      .units(
        allowed: [.hours, .minutes, .seconds],
        width: .narrow
      )
    )
  }

  private func descriptionSection(_ description: AttributedString) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Description")
        .font(.headline)

      Text(description)
        .font(.subheadline)
    }
    .textSelection(.enabled)
  }
}

extension BookDetailsView {
  @Observable
  class Model: ObservableObject {
    let bookID: String
    var title: String
    var authors: [Author]
    var narrators: [String]
    var series: [Series]
    var coverURL: URL?
    var progress: Double?
    var durationText: String?
    var timeRemaining: String?
    var chapters: [Chapter]?
    var tracks: [Track]?
    var downloadState: DownloadManager.DownloadState
    var isLoading: Bool
    var isEbook: Bool
    var isCurrentlyPlaying: Bool
    var error: String?
    var publisher: String?
    var publishedYear: String?
    var genres: [String]?
    var tags: [String]?
    var description: AttributedString?

    func onAppear() {}
    func onPlayTapped() {}
    func onDownloadTapped() {}
    func onMarkFinishedTapped() {}

    init(
      bookID: String,
      title: String = "",
      authors: [Author] = [],
      narrators: [String] = [],
      series: [Series] = [],
      coverURL: URL? = nil,
      progress: Double? = nil,
      durationText: String? = nil,
      timeRemaining: String? = nil,
      chapters: [Chapter]? = nil,
      tracks: [Track]? = nil,
      downloadState: DownloadManager.DownloadState = .notDownloaded,
      isLoading: Bool = true,
      isEbook: Bool = false,
      isCurrentlyPlaying: Bool = false,
      error: String? = nil,
      publisher: String? = nil,
      publishedYear: String? = nil,
      genres: [String]? = nil,
      tags: [String]? = nil,
      description: AttributedString? = nil
    ) {
      self.bookID = bookID
      self.title = title
      self.authors = authors
      self.narrators = narrators
      self.series = series
      self.coverURL = coverURL
      self.progress = progress
      self.durationText = durationText
      self.timeRemaining = timeRemaining
      self.chapters = chapters
      self.tracks = tracks
      self.downloadState = downloadState
      self.isLoading = isLoading
      self.isEbook = isEbook
      self.isCurrentlyPlaying = isCurrentlyPlaying
      self.error = error
      self.publisher = publisher
      self.publishedYear = publishedYear
      self.genres = genres
      self.tags = tags
      self.description = description
    }
  }
}

extension BookDetailsView.Model {
  struct Author {
    let id: String
    let name: String
  }

  struct Series {
    let id: String
    let name: String
    let sequence: String
  }
}

extension BookDetailsView.Model {
  static var mock: BookDetailsView.Model {
    BookDetailsView.Model(
      bookID: "mock-id",
      title: "The Lord of the Rings",
      authors: [
        Author(id: "author-1", name: "J.R.R. Tolkien")
      ],
      narrators: ["Rob Inglis"],
      series: [
        Series(id: "series-1", name: "The Lord of the Rings", sequence: "1")
      ],
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
      progress: 0.45,
      durationText: "12hr 30min",
      timeRemaining: "6hr 52min",
      chapters: [
        .init(id: 1, start: 0, end: 1000, title: "001"),
        .init(id: 2, start: 1001, end: 2000, title: "002"),
        .init(id: 3, start: 2001, end: 3000, title: "003"),
        .init(id: 4, start: 3001, end: 4000, title: "004"),
        .init(id: 5, start: 4001, end: 5000, title: "005"),
        .init(id: 6, start: 5001, end: 6000, title: "006"),
      ],
      tracks: [],
      downloadState: .downloaded,
      isLoading: false,
      description:
        "As the Colony continues to develop and thrive, there's too much to do! Territory to seize, nests to build, Champions to train! Anthony will have his mandibles full trying to teach his new protege Brilliant while trying to keep a war from breaking out with the ka'armodo. However, when the Mother Tree comes looking for his help against a particular breed of monster, there is no way he can refuse. After all, no ant can resist a fight against their ancient nemesis... the Termite! Book 7 of the hit monster-evolution LitRPG series with nearly 30 Million views on Royal Road. Grab your copy today!"
    )
  }
}

#Preview {
  NavigationStack {
    BookDetailsView(model: .mock)
  }
}

struct ParallaxHeader<Content: View, Space: Hashable>: View {
  let content: () -> Content
  let coordinateSpace: Space
  @State var height: CGFloat = 0

  init(
    coordinateSpace: Space,
    @ViewBuilder _ content: @escaping () -> Content
  ) {
    self.content = content
    self.coordinateSpace = coordinateSpace
  }

  var body: some View {
    GeometryReader { proxy in
      let offset = offset(for: proxy)
      let heightModifier = heightModifier(for: proxy)
      content()
        .edgesIgnoringSafeArea(.horizontal)
        .frame(
          width: proxy.size.width,
          height: proxy.size.height + heightModifier
        )
        .offset(y: offset)
        .onAppear {
          height = min(370, proxy.size.width)
        }
        .onChange(of: proxy.size.width) { _, new in height = min(370, new) }
    }
    .frame(height: height)
  }

  private func offset(for proxy: GeometryProxy) -> CGFloat {
    let frame = proxy.frame(in: .named(coordinateSpace))
    if frame.minY < 0 {
      return -frame.minY * 0.8
    }
    return -frame.minY
  }

  private func heightModifier(for proxy: GeometryProxy) -> CGFloat {
    let frame = proxy.frame(in: .named(coordinateSpace))
    return max(0, frame.minY)
  }
}
