import API
import Combine
import CoreNFC
import Models
import RichText
import SwiftUI

struct BookDetailsView: View {
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  @StateObject var model: Model

  @State private var collectionSelector: CollectionMode?
  @State private var selectedTabIndex: Int = 0
  @State private var isDescriptionExpanded: Bool = false
  @State private var isShowingFullScreenCover = false

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
    .fullScreenCover(item: $model.ebookReader) { model in
      NavigationStack {
        EbookReaderView(model: model)
      }
    }
    .fullScreenCover(isPresented: $isShowingFullScreenCover) {
      if let coverURL = model.coverURL {
        FullScreenCoverView(coverURL: coverURL)
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
      if model.downloadState != .downloaded {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.onDownloadTapped()
          } label: {
            switch model.downloadState {
            case .notDownloaded:
              Label("Download", systemImage: "arrow.down.circle")
            case .downloading:
              Label("Cancel", systemImage: "stop.circle")
            case .downloaded:
              EmptyView()
            }
          }
          .tint(.primary)
        }

        if #available(iOS 26.0, *) {
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          if model.actions.contains(.addToCollection) {
            Button(action: { collectionSelector = .collections }) {
              Label("Add to Collection", systemImage: "square.stack.3d.up.fill")
            }
          }

          Button(action: { collectionSelector = .playlists }) {
            Label("Add to Playlist", systemImage: "music.note.list")
          }

          if model.actions.contains(.viewBookmarks) {
            Button(action: { model.bookmarks?.isPresented = true }) {
              Label("Your Bookmarks", systemImage: "bookmark.fill")
            }
          }

          if Audiobookshelf.shared.authentication.permissions?.download == true {
            Button(action: { model.onDownloadTapped() }) {
              switch model.downloadState {
              case .downloading:
                Label("Cancel", systemImage: "stop.circle")
              case .downloaded:
                Label("Remove Download", systemImage: "trash")
              case .notDownloaded:
                Label("Download", systemImage: "arrow.down.circle")
              }
            }
          }

          if model.actions.contains(.addToQueue) {
            Button(action: model.onAddToQueueTapped) {
              Label("Add to Queue", systemImage: "text.badge.plus")
            }
          } else if model.actions.contains(.removeFromQueue) {
            Button(action: model.onRemoveFromQueueTapped) {
              Label("Remove from Queue", systemImage: "text.badge.minus")
            }
          }

          if model.actions.contains(.markAsFinished) {
            Button(action: model.onMarkFinishedTapped) {
              Label("Mark as Finished", systemImage: "checkmark.shield")
            }
          }

          if model.actions.contains(.resetProgress) {
            Button(action: model.onResetProgressTapped) {
              Label("Reset Progress", systemImage: "arrow.counterclockwise")
            }
          }

          ereaderDevices

          if model.actions.contains(.writeNFCTag) {
            Divider()

            Button(action: model.onWriteTagTapped) {
              Label("Write NFC tag", systemImage: "sensor.tag.radiowaves.forward")
            }
          }
        } label: {
          Image(systemName: "ellipsis")
        }
        .tint(.primary)
      }
    }
    .sheet(item: $collectionSelector) { mode in
      CollectionSelectorSheet(
        model: CollectionSelectorSheetModel(bookID: model.bookID, mode: mode)
      )
    }
    .sheet(
      isPresented: Binding(
        get: { model.bookmarks?.isPresented ?? false },
        set: { newValue in model.bookmarks?.isPresented = newValue }
      )
    ) {
      if let bookmarks = model.bookmarks {
        BookmarkViewerSheet(model: bookmarks)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private var portraitLayout: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          cover(offset: proxy.safeAreaInsets.top)
            .frame(height: 266 + proxy.safeAreaInsets.top)

          contentSections
            .padding()
            .background()
        }
        .padding(.vertical)
      }
      .coordinateSpace(name: CoordinateSpaces.scrollView)
      .ignoresSafeArea(edges: .top)
    }
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
      title

      actionButtons

      headerSection
      MetadataSection(model: model.metadata)
      if let description = model.description {
        descriptionSection(description)
      }
      if let genres = model.genres, !genres.isEmpty {
        genresSection(genres)
      }
      if let tags = model.tags, !tags.isEmpty {
        tagsSection(tags)
      }
      if !model.tabs.isEmpty {
        contentTabsSection
      }
    }
    .buttonStyle(.borderless)
  }

  private var title: some View {
    var result = Text(model.title)
      .font(.title)
      .fontWeight(.bold)

    if model.flags.contains(.explicit) {
      result =
        result
        + Text(" \(Image(systemName: "e.square.fill"))")
        .font(.footnote)
        .baselineOffset(8)
        .foregroundStyle(.secondary)
    }

    if model.flags.contains(.abridged) {
      result =
        result
        + Text(" \(Image(systemName: "a.square.fill"))")
        .font(.footnote)
        .baselineOffset(8)
        .foregroundStyle(.secondary)
    }

    return VStack(alignment: .leading, spacing: 4) {
      result
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      if let subtitle = model.subtitle {
        Text(subtitle)
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var contentTabsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.tabs.count > 1 {
        Picker("Content", selection: $selectedTabIndex) {
          ForEach(model.tabs.indices, id: \.self) { index in
            Text(model.tabs[index].title).tag(index)
          }
        }
        .pickerStyle(.segmented)
      } else if let firstTab = model.tabs.first {
        Text(firstTab.title)
          .font(.headline)
      }

      if model.tabs.indices.contains(selectedTabIndex) {
        switch model.tabs[selectedTabIndex] {
        case .chapters(let chaptersModel):
          ChaptersContent(model: chaptersModel)
        case .tracks(let tracksModel):
          TracksContent(model: tracksModel)
        case .ebooks(let ebooksModel):
          EbooksContent(model: ebooksModel)
        }
      }
    }
    .onChange(of: model.tabs.count) { _, newCount in
      if selectedTabIndex >= newCount {
        selectedTabIndex = 0
      }
    }
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

        LazyImage(url: model.coverURL) { state in
          if let image = state.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
          } else {
            Color.gray.opacity(0.3)
              .overlay {
                Image(systemName: "book.closed")
                  .foregroundColor(.gray)
                  .font(.title2)
              }
          }
        }
        .overlay(alignment: .bottom) {
          if let progress = model.progress, progress > 0 {
            ProgressBarView(progress: model.progress)
          }
        }
        .overlay { downloadProgress }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
      CoverImage(url: model.coverURL)
        .frame(width: 200, height: 200)
        .overlay(alignment: .bottom) {
          if let progress = model.progress, progress > 0 {
            ProgressBarView(progress: model.progress)
          }
        }
        .overlay { downloadProgress }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

  @ViewBuilder
  var downloadProgress: some View {
    if case .downloading(let progress) = model.downloadState {
      ZStack {
        Color.black.opacity(0.6)

        Button(
          action: { model.onDownloadTapped() },
          label: {
            ProgressView(value: progress)
              .progressViewStyle(GaugeProgressViewStyle(tint: .white, lineWidth: 6))
              .frame(width: 100, height: 100)
              .overlay {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                  .font(.system(size: 20))
                  .fontWeight(.medium)
                  .foregroundStyle(Color.white)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .contentShape(Rectangle())
          }
        )
        .buttonStyle(.plain)
      }
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !model.authors.isEmpty || (model.metadata.hasAudio && !model.narrators.isEmpty) {
        VStack(alignment: .leading, spacing: 12) {
          Text(model.metadata.hasAudio ? "Authors & Narrators" : "Authors")
            .font(.headline)

          FlowLayout(spacing: 4) {
            ForEach(model.authors, id: \.id) { author in
              NavigationLink(value: NavigationDestination.author(id: author.id, name: author.name)) {
                Chip(
                  title: author.name,
                  icon: "person.circle.fill",
                  color: .blue
                )
                .accessibilityLabel("\(author.name) author")
              }
            }

            if model.metadata.hasAudio {
              ForEach(model.narrators, id: \.self) { narrator in
                NavigationLink(value: NavigationDestination.narrator(name: narrator)) {
                  Chip(
                    title: narrator,
                    icon: "person.wave.2.fill",
                    color: .blue
                  )
                  .accessibilityLabel("\(narrator) narrator")
                }
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
              NavigationLink(value: NavigationDestination.series(id: series.id, name: series.name)) {
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

  private var actionButtons: some View {
    VStack(spacing: 12) {
      if model.metadata.hasAudio {
        Button(action: model.onPlayTapped) {
          Label(
            playButtonText,
            systemImage: model.isPlaying ? "pause.fill" : "play.fill"
          )
          .frame(maxWidth: .infinity)
          .padding()
          .background {
            actionBackground(progress: model.metadata.audioProgress)
          }
          .foregroundColor(.white)
          .cornerRadius(12)
        }
      }

      if model.metadata.isEbook {
        Button(action: model.onReadTapped) {
          Label("Read", systemImage: "book.fill")
            .frame(maxWidth: .infinity)
            .padding()
            .background {
              actionBackground(progress: model.metadata.ebookProgress)
            }
            .foregroundColor(.white)
            .cornerRadius(12)
        }
      }
    }
  }

  private var playButtonText: String {
    if model.isPlaying {
      "Pause"
    } else if let audioProgress = model.metadata.audioProgress, audioProgress > 0 {
      "Continue Listening"
    } else {
      "Play"
    }
  }

  @ViewBuilder
  func actionBackground(progress: Double?) -> some View {
    if let progress, progress >= 0.01 {
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
}

extension BookDetailsView {
  @ViewBuilder
  private var ereaderDevices: some View {
    if model.actions.contains(.openOnWeb) {
      Divider()

      Button(
        action: { model.onOpenTapped() },
        label: {
          Label("Open on Web", systemImage: "globe")
        }
      )

      if model.actions.contains(.sendToEbook) {
        Menu {
          ForEach(model.ereaderDevices, id: \.self) { device in
            Button(device) {
              model.onSendToEbookTapped(device)
            }
          }
        } label: {
          Label("Send Ebook to", systemImage: "paperplane")
        }
      }
    }
  }
}

extension BookDetailsView {
  @Observable
  class Model: ObservableObject {
    struct Flags: OptionSet {
      let rawValue: Int

      static let explicit = Flags(rawValue: 1 << 0)
      static let abridged = Flags(rawValue: 1 << 1)
    }

    struct Actions: OptionSet {
      let rawValue: Int

      static let addToCollection = Actions(rawValue: 1 << 0)
      static let viewBookmarks = Actions(rawValue: 1 << 1)
      static let addToQueue = Actions(rawValue: 1 << 2)
      static let removeFromQueue = Actions(rawValue: 1 << 3)
      static let markAsFinished = Actions(rawValue: 1 << 4)
      static let resetProgress = Actions(rawValue: 1 << 5)
      static let writeNFCTag = Actions(rawValue: 1 << 6)
      static let openOnWeb = Actions(rawValue: 1 << 7)
      static let sendToEbook = Actions(rawValue: 1 << 8)
    }

    let bookID: String
    var title: String
    var subtitle: String?
    var authors: [Author]
    var narrators: [String]
    var series: [Series]
    var coverURL: URL?
    var progress: Double?
    var downloadState: DownloadManager.DownloadState
    var isLoading: Bool
    var isPlaying: Bool
    var flags: Flags
    var error: String?
    var genres: [String]?
    var tags: [String]?
    var description: String?
    var actions: Actions
    var bookmarks: BookmarkViewerSheet.Model?
    var ereaderDevices: [String]
    var ebookReader: EbookReaderView.Model?

    var tabs: [ContentTab]
    var metadata: MetadataSection.Model

    func onAppear() {}
    func onPlayTapped() {}
    func onReadTapped() {}
    func onOpenTapped() {}
    func onDownloadTapped() {}
    func onMarkFinishedTapped() {}
    func onResetProgressTapped() {}
    func onWriteTagTapped() {}
    func onSendToEbookTapped(_ device: String) {}
    func onAddToQueueTapped() {}
    func onRemoveFromQueueTapped() {}

    init(
      bookID: String,
      title: String = "",
      subtitle: String? = nil,
      authors: [Author] = [],
      narrators: [String] = [],
      series: [Series] = [],
      coverURL: URL? = nil,
      progress: Double? = nil,
      downloadState: DownloadManager.DownloadState = .downloaded,
      isLoading: Bool = true,
      isCurrentlyPlaying: Bool = false,
      flags: Flags = [],
      error: String? = nil,
      genres: [String]? = nil,
      tags: [String]? = nil,
      description: String? = nil,
      actions: Actions = [],
      bookmarks: BookmarkViewerSheet.Model? = nil,
      ereaderDevices: [String] = [],
      ebookReader: EbookReaderView.Model? = nil,
      tabs: [ContentTab],
      metadata: MetadataSection.Model = .init()
    ) {
      self.bookID = bookID
      self.title = title
      self.subtitle = subtitle
      self.authors = authors
      self.narrators = narrators
      self.series = series
      self.coverURL = coverURL
      self.progress = progress
      self.downloadState = downloadState
      self.isLoading = isLoading
      self.isPlaying = isCurrentlyPlaying
      self.flags = flags
      self.error = error
      self.genres = genres
      self.tags = tags
      self.description = description
      self.actions = actions
      self.bookmarks = bookmarks
      self.ereaderDevices = ereaderDevices
      self.ebookReader = ebookReader
      self.tabs = tabs
      self.metadata = metadata
    }
  }
}

extension BookDetailsView.Model {
  enum ContentTab {
    case chapters(ChaptersContent.Model)
    case tracks(TracksContent.Model)
    case ebooks(EbooksContent.Model)

    var title: String {
      switch self {
      case .chapters: "Chapters"
      case .tracks: "Tracks"
      case .ebooks: "eBooks"
      }
    }
  }

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
    let chapters: [ChaptersContent.Chapter] = [
      .init(id: 1, start: 0, end: 1000, title: "001", status: .completed),
      .init(id: 2, start: 1001, end: 2000, title: "002", status: .completed),
      .init(id: 3, start: 2001, end: 3000, title: "003", status: .current),
      .init(id: 4, start: 3001, end: 4000, title: "004", status: .remaining),
      .init(id: 5, start: 4001, end: 5000, title: "005", status: .remaining),
      .init(id: 6, start: 5001, end: 6000, title: "006", status: .remaining),
    ]

    let tracks: [Track] = [
      .init(
        index: 1,
        startOffset: 0,
        duration: 45000,
        filename: "The Lord of the Rings.m4b",
        size: 552_003_086,
        bitRate: 128000,
        codec: "aac"
      )
    ]

    return BookDetailsView.Model(
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
      downloadState: .downloaded,
      isLoading: false,
      flags: [.explicit],
      description:
        "As the Colony continues to develop and thrive, there's too much to do! Territory to seize, nests to build, Champions to train! Anthony will have his mandibles full trying to teach his new protege Brilliant while trying to keep a war from breaking out with the ka'armodo. However, when the Mother Tree comes looking for his help against a particular breed of monster, there is no way he can refuse. After all, no ant can resist a fight against their ancient nemesis... the Termite! Book 7 of the hit monster-evolution LitRPG series with nearly 30 Million views on Royal Road. Grab your copy today!",
      tabs: [
        .chapters(ChaptersContent.Model(chapters: chapters)),
        .tracks(TracksContent.Model(tracks: tracks)),
      ],
      metadata: .init(
        durationText: "12hr 30min",
        timeRemaining: "6hr 52min",
        hasAudio: true
      )
    )
  }
}

#Preview {
  NavigationStack {
    BookDetailsView(model: .mock)
  }
}
