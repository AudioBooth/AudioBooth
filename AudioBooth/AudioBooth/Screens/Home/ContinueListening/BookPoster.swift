import Combine
import Nuke
import NukeUI
import SwiftUI

struct BookPoster: View {
  @StateObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  @Environment(\.posterWidth) private var customWidth
  @ScaledMetric(relativeTo: .title) private var defaultWidth: CGFloat = 200

  private var book: BookCard.Model { model.book }

  private var width: CGFloat {
    customWidth ?? defaultWidth
  }

  private var isCompact: Bool {
    width <= defaultWidth
  }

  private var backgroundColor: Color {
    model.backgroundColor ?? Color(white: 0.25)
  }

  private var navigationDestination: NavigationDestination {
    if let id = book.podcastID {
      .podcast(id: id, episodeID: book.id == id ? nil : book.id)
    } else {
      .book(id: book.id)
    }
  }

  var body: some View {
    DestinationLink(destination: navigationDestination, zooms: true) {
      content
    }
    .buttonStyle(.plain)
    .contextMenu {
      contextMenuItems
    }
    .menuOrder(.priority)
    .bookCardAccessibilityActions(model: book)
    .bookCardCollectionSelector(model: book)
    .onAppear(perform: book.onAppear)
  }

  @ViewBuilder
  private var contextMenuItems: some View {
    if let menu = book.contextMenu {
      BookCardContextMenu(model: menu)
    } else if let menu = book.episodeContextMenu {
      PodcastEpisodeContextMenu(model: menu)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let author = book.author, !author.isEmpty {
        Text(author)
          .font(.caption2)
          .fontWeight(.medium)
          .textCase(.uppercase)
          .foregroundStyle(.white.opacity(0.85))
          .lineLimit(1)
          .shadow(color: .black.opacity(0.9), radius: 1)
      }

      Text(book.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(2)
        .shadow(color: .black.opacity(0.9), radius: 1)

      if let summary = book.summary, !summary.isEmpty {
        Text(summary)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.75))
          .lineLimit(2)
          .shadow(color: .black.opacity(0.9), radius: 1)
      }

      controls
        .padding(.top, 4)
    }
    .multilineTextAlignment(.leading)
    .padding(16)
    .background {
      LinearGradient(
        colors: [0, 0.5, 0.75, 0.8, 0.85, 0.9, 0.95, 1].map { backgroundColor.opacity($0) },
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .frame(width: width, height: width * 1.35, alignment: .bottomLeading)
    .background(alignment: .top) {
      artwork
    }
    .background(backgroundColor)
    .clipShape(.rect(cornerRadius: 16))
    .contentShape(.rect(cornerRadius: 16))
  }

  private var artwork: some View {
    LazyImage(request: book.cover.url.map { ImageRequest(url: $0, processors: [.resize(width: width)]) }) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.clear
      }
    }
    .frame(width: width, height: width)
    .clipped()
    .mask {
      LinearGradient(
        stops: [
          .init(color: .black, location: 0.8),
          .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .overlay(alignment: .top) {
      HStack {
        if book.hasEbook {
          coverBadge(systemImage: "book.fill")
        }

        Spacer()

        if let downloadProgress = book.cover.downloadProgress {
          downloadProgressBadge(downloadProgress)
        } else if book.isDownloaded {
          coverBadge(systemImage: "arrow.down.circle.fill")
        }
      }
      .padding(8)
    }
  }

  private func downloadProgressBadge(_ progress: Double) -> some View {
    ProgressView(value: progress)
      .progressViewStyle(GaugeProgressViewStyle(tint: .white, lineWidth: 2))
      .frame(width: 12, height: 12)
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(.black.opacity(0.6), in: .capsule)
      .accessibilityLabel("Downloading…")
  }

  private func coverBadge(systemImage: String) -> some View {
    Image(systemName: systemImage)
      .font(isCompact ? .caption2 : .caption)
      .foregroundStyle(.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(.black.opacity(0.6), in: .capsule)
  }

  private var controls: some View {
    HStack {
      Button(action: model.onPlayTapped) {
        HStack(spacing: 8) {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")

          if let progress = book.cover.progress, progress > 0, progress < 1 {
            ProgressView(value: progress)
              .tint(.black)
              .frame(minWidth: 12, maxWidth: 32)
          }

          if let label = preferences.showContinueTimeRemaining ? model.playText : model.progressText {
            Text(label)
              .font(isCompact ? .footnote : .subheadline)
              .lineLimit(1)
              .fixedSize()
          }
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white, in: .capsule)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
      .accessibilityValue(book.timeRemaining?.accessibilityTimeRemaining ?? "")

      Spacer(minLength: 0)

      Menu {
        contextMenuItems
      } label: {
        Image(systemName: "ellipsis")
          .font(.body)
          .fontWeight(.semibold)
          .foregroundStyle(.white.opacity(0.8))
          .frame(width: 32, height: 32)
          .contentShape(.rect)
      }
      .menuOrder(.priority)
      .accessibilityLabel("More")
    }
  }
}

extension BookPoster {
  @Observable
  class Model: ObservableObject, Identifiable {
    let book: BookCard.Model
    var isPlaying = false
    var backgroundColor: Color?

    var id: String { book.id }

    var playText: String? {
      guard let timeRemaining = book.timeRemaining, timeRemaining > 0 else { return nil }
      return Duration.seconds(timeRemaining).formatted(
        .units(allowed: [.hours, .minutes], width: .narrow)
      )
    }

    var progressText: String? {
      guard let progress = book.cover.progress, progress > 0 else { return nil }
      return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    func onPlayTapped() {}

    init(book: BookCard.Model, isPlaying: Bool = false, backgroundColor: Color? = nil) {
      self.book = book
      self.isPlaying = isPlaying
      self.backgroundColor = backgroundColor
    }
  }
}

#Preview {
  NavigationStack {
    BookPoster(
      model: BookPoster.Model(
        book: BookCard.Model(
          title: "The Lord of the Rings",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            progress: 0.45
          ),
          author: "J.R.R. Tolkien",
          timeRemaining: 30720
        ),
        backgroundColor: Color(hue: 0.6, saturation: 0.2, brightness: 0.3)
      )
    )
    .padding()
  }
}
