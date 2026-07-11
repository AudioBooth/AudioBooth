import API
import Combine
import SwiftUI

extension EnvironmentValues {
  @Entry var itemDisplayMode: BookCard.DisplayMode = .card
  @Entry var coverSize: CGFloat? = nil
}

struct BookCard: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationLink(value: navigationDestination) {
      Content(model: model)
    }
    .buttonStyle(.plain)
    .contextMenu {
      if let model = model.contextMenu {
        BookCardContextMenu(model: model)
      } else if let model = model.episodeContextMenu {
        PodcastEpisodeContextMenu(model: model)
      }
    }
    .bookCardAccessibilityActions(model: model)
    .sheet(
      item: Binding(
        get: { model.contextMenu?.collectionSelector },
        set: { model.contextMenu?.collectionSelector = $0 }
      )
    ) { sheetModel in
      CollectionSelectorSheet(model: sheetModel)
    }
    .onAppear(perform: model.onAppear)
  }

  private var navigationDestination: NavigationDestination {
    if let id = model.podcastID {
      .podcast(id: id, episodeID: model.id)
    } else {
      .book(id: model.id)
    }
  }
}

struct BookListCard: View {
  @ObservedObject var model: BookCard.Model
  @Environment(\.editMode) private var editMode

  private var isEditing: Bool {
    editMode?.wrappedValue.isEditing ?? false
  }

  var body: some View {
    BookCard.Content(model: model)
      .contentShape(Rectangle())
      .overlay {
        if !isEditing {
          NavigationLink(value: navigationDestination) {}
            .opacity(0)
        }
      }
      .contextMenu {
        if let model = model.contextMenu {
          BookCardContextMenu(model: model)
        } else if let model = model.episodeContextMenu {
          PodcastEpisodeContextMenu(model: model)
        }
      }
      .bookCardAccessibilityActions(model: model)
      .sheet(
        item: Binding(
          get: { model.contextMenu?.collectionSelector },
          set: { model.contextMenu?.collectionSelector = $0 }
        )
      ) { sheetModel in
        CollectionSelectorSheet(model: sheetModel)
      }
      .onAppear(perform: model.onAppear)
  }

  private var navigationDestination: NavigationDestination {
    if let id = model.podcastID {
      .podcast(id: id, episodeID: model.id)
    } else {
      .book(id: model.id)
    }
  }
}

extension BookCard {
  struct Content: View {
    let model: BookCard.Model
    @Environment(\.itemDisplayMode) private var displayMode
    @Environment(\.coverSize) private var coverSize
    @Environment(\.editMode) private var editMode
    @ObservedObject private var preferences = UserPreferences.shared

    @ScaledMetric(relativeTo: .title) private var rowCoverSize: CGFloat = 60
    @ScaledMetric(relativeTo: .caption2) private var subtitleFontSize: CGFloat = 10
    @State private var coverWidth: CGFloat = .infinity

    private var isEditing: Bool {
      editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
      switch displayMode {
      case .card:
        cardLayout
      case .row:
        rowLayout
      }
    }

    private var cardLayout: some View {
      VStack(alignment: .leading, spacing: 8) {
        cover
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: { width in
            coverWidth = width
          }

        VStack(alignment: .leading, spacing: 8) {
          if !preferences.cardMinimalMode {
            VStack(alignment: .leading, spacing: 2) {
              title

              if preferences.showBookSubtitle, let subtitle = model.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                  .font(.system(size: subtitleFontSize))
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }

              details
            }
            .multilineTextAlignment(.leading)
          } else if preferences.showContinueTimeRemaining, let timeRemaining = model.timeRemaining {
            Text(timeRemaining.formattedTimeRemaining)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
              .allowsTightening(true)
              .multilineTextAlignment(.leading)
              .accessibilityLabel(timeRemaining.accessibilityTimeRemaining)
          }
        }
        .frame(maxWidth: coverWidth, alignment: .leading)
      }
      .contentShape(Rectangle())
    }

    private var rowLayout: some View {
      HStack(spacing: 12) {
        rowCover

        VStack(alignment: .leading, spacing: 4) {
          title

          if preferences.showBookSubtitle, let subtitle = model.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: subtitleFontSize))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          if let author = model.author {
            rowMetadata(icon: "pencil", value: author)
          }

          if let details = model.details {
            Text(details)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          } else if let narrator = model.narrator, !narrator.isEmpty {
            rowMetadata(icon: "person.wave.2.fill", value: narrator)
          }

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let publishedYear = model.publishedYear {
          Text(publishedYear)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if !isEditing {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }

    private var cover: some View {
      Cover(model: model.cover)
        .frame(height: coverSize)
        .overlay(alignment: .bottom) {
          HStack {
            ebookIndicator
              .padding(4)

            Spacer()

            downloadedIndicator
              .padding(4)
          }
        }
        .overlay(alignment: .topTrailing) {
          if let sequence = model.sequence, !sequence.isEmpty {
            badge {
              Text(verbatim: "#\(sequence)")
            }
          }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func badge(content: () -> some View) -> some View {
      content()
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(Color.white)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(.capsule)
        .padding(4)
    }

    private var rowCover: some View {
      Cover(model: model.cover, size: .small)
        .overlay(alignment: .bottom) {
          HStack {
            ebookIndicator
              .padding(2)

            Spacer()

            downloadedIndicator
              .padding(2)
          }
        }
        .overlay(alignment: .topTrailing) {
          if let sequence = model.sequence, !sequence.isEmpty {
            Text(verbatim: "#\(sequence)")
              .font(.caption2)
              .fontWeight(.medium)
              .foregroundStyle(Color.white)
              .padding(.vertical, 2)
              .padding(.horizontal, 4)
              .background(Color.black.opacity(0.6))
              .clipShape(.capsule)
              .padding(2)
          }
        }
        .frame(width: rowCoverSize, height: rowCoverSize)
    }

    private func rowMetadata(icon: String, value: String) -> some View {
      HStack(spacing: 4) {
        if model.details == nil {
          Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Text(value)
          .font(.caption2)
          .foregroundColor(.primary)
      }
      .lineLimit(1)
    }

    private var title: some View {
      HStack(spacing: 4) {
        Text(model.title)
          .font(.caption)
          .foregroundColor(.primary)
          .fontWeight(.medium)
          .lineLimit(1)
          .allowsTightening(true)

        if model.isExplicit {
          Image(systemName: "e.square.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

      }
    }

    @ViewBuilder
    private var details: some View {
      if preferences.showContinueTimeRemaining, let timeRemaining = model.timeRemaining {
        detailsLabel(timeRemaining.formattedTimeRemaining)
          .accessibilityLabel(timeRemaining.accessibilityTimeRemaining)
      } else if let text = detailsText {
        detailsLabel(text)
      }
    }

    private func detailsLabel(_ text: String) -> some View {
      Text(text)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .allowsTightening(true)
    }

    private var detailsText: String? {
      if model.timeRemaining != nil {
        return model.author
      }
      return model.details ?? model.author
    }

    @ViewBuilder
    private var ebookIndicator: some View {
      if model.hasEbook {
        coverBadge(systemImage: "book.fill")
      }
    }

    @ViewBuilder
    private var downloadedIndicator: some View {
      if model.isDownloaded {
        coverBadge(systemImage: "arrow.down.circle.fill")
      }
    }

    private func coverBadge(systemImage: String) -> some View {
      Image(systemName: systemImage)
        .font(.caption2)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 4)
        .frame(height: 16)
        .background(Color.black.opacity(0.6))
        .clipShape(.capsule)
    }
  }
}

extension BookCard {
  enum DisplayMode: RawRepresentable {
    case card
    case row

    var rawValue: String {
      switch self {
      case .card: "card"
      case .row: "row"
      }
    }

    init?(rawValue: String) {
      switch rawValue {
      case "card", "grid":
        self = .card
      case "row", "list":
        self = .row
      default:
        return nil
      }
    }

  }

  struct Author {
    let id: String
    let name: String
  }

  struct Narrator {
    let name: String
  }

  struct Series {
    let id: String
    let name: String
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let podcastID: String?
    let title: String
    let subtitle: String?
    var details: String?
    let cover: Cover.Model
    let sequence: String?
    let author: String?
    let narrator: String?
    let publishedYear: String?
    var contextMenu: BookCardContextMenu.Model?
    var episodeContextMenu: PodcastEpisodeContextMenu.Model?
    let hasEbook: Bool
    var isDownloaded: Bool
    let isExplicit: Bool
    var timeRemaining: TimeInterval?

    func onAppear() {}

    init(
      id: String = UUID().uuidString,
      podcastID: String? = nil,
      title: String,
      subtitle: String? = nil,
      details: String? = nil,
      cover: Cover.Model = Cover.Model(url: nil),
      sequence: String? = nil,
      author: String? = nil,
      narrator: String? = nil,
      publishedYear: String? = nil,
      contextMenu: BookCardContextMenu.Model? = nil,
      episodeContextMenu: PodcastEpisodeContextMenu.Model? = nil,
      hasEbook: Bool = false,
      isDownloaded: Bool = false,
      isExplicit: Bool = false,
      timeRemaining: TimeInterval? = nil
    ) {
      self.id = id
      self.podcastID = podcastID
      self.title = title
      self.subtitle = subtitle
      self.details = details
      self.cover = cover
      self.sequence = sequence
      self.author = author
      self.narrator = narrator
      self.publishedYear = publishedYear
      self.contextMenu = contextMenu
      self.episodeContextMenu = episodeContextMenu
      self.hasEbook = hasEbook
      self.isDownloaded = isDownloaded
      self.isExplicit = isExplicit
      self.timeRemaining = timeRemaining
    }
  }
}

#Preview("BookCard - Card Mode") {
  NavigationStack {
    LazyVGrid(
      columns: [
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
      ],
      spacing: 20
    ) {
      BookCard(
        model: BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            progress: 0.5
          )
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Foundation",
          details: "Isaac Asimov",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
        )
      )
    }
    .padding()
  }
}

#Preview("BookCard - Row Mode") {
  NavigationStack {
    ScrollView {
      VStack(spacing: 12) {
        BookCard(
          model: BookCard.Model(
            title: "The Lord of the Rings",
            details: "J.R.R. Tolkien",
            cover: Cover.Model(
              url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
              progress: 0.5
            ),
            sequence: "1",
            author: "J.R.R. Tolkien",
            narrator: "Rob Inglis",
            publishedYear: "1954"
          )
        )
        BookCard(
          model: BookCard.Model(
            title: "Dune",
            details: "Frank Herbert",
            cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")),
            author: "Frank Herbert",
            narrator: "Scott Brick, Orlagh Cassidy, Euan Morton",
            publishedYear: "1965"
          )
        )
        BookCard(
          model: BookCard.Model(
            title: "Foundation",
            details: "Isaac Asimov",
            cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")),
            author: "Isaac Asimov",
            narrator: "Scott Brick",
            publishedYear: "1951"
          )
        )
      }
    }
    .environment(\.itemDisplayMode, .row)
    .padding()
  }
}
