import Combine
import Nuke
import NukeUI
import SwiftUI

struct EpisodeCard: View {
  @ObservedObject var model: Model

  @ScaledMetric(relativeTo: .title) private var width: CGFloat = 260

  private var backgroundColor: Color {
    model.backgroundColor ?? Color(white: 0.25)
  }

  var body: some View {
    DestinationLink(
      destination: .podcast(id: model.podcastID, episodeID: model.id),
      zooms: true
    ) {
      content
    }
    .buttonStyle(.plain)
    .contextMenu {
      PodcastEpisodeContextMenu(model: model.contextMenu)
    }
    .menuOrder(.priority)
    .podcastEpisodeAccessibilityActions(episodeID: model.id, menu: model.contextMenu)
    .sheet(
      item: Binding(
        get: { model.contextMenu.collectionSelector },
        set: { model.contextMenu.collectionSelector = $0 }
      )
    ) { sheetModel in
      CollectionSelectorSheet(model: sheetModel)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      Spacer(minLength: 0)

      if let publishedAt = model.publishedAt {
        Text(publishedAt.formatted(.dateTime.day().month(.wide).year()))
          .font(.caption2)
          .fontWeight(.medium)
          .textCase(.uppercase)
          .foregroundStyle(.white.opacity(0.7))
      }

      Text(model.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(2)

      if let summary = model.summary, !summary.isEmpty {
        Text(summary)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.75))
          .lineLimit(2)
      }

      controls
        .padding(.top, 4)
    }
    .multilineTextAlignment(.leading)
    .padding(16)
    .frame(width: width, height: width * 1.35, alignment: .bottomLeading)
    .background(alignment: .top) {
      artwork
    }
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .contentShape(RoundedRectangle(cornerRadius: 16))
  }

  private var artwork: some View {
    LazyImage(request: model.coverURL.map { ImageRequest(url: $0, processors: [.resize(width: width)]) }) { state in
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
          .init(color: .black, location: 0.5),
          .init(color: .black.opacity(0.15), location: 0.75),
          .init(color: .clear, location: 0.95),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private var controls: some View {
    HStack {
      Button(action: model.onPlayTapped) {
        HStack(spacing: 8) {
          Image(systemName: "play.fill")

          if model.progress > 0 && model.progress < 1 {
            ProgressView(value: model.progress)
              .tint(.black)
              .frame(width: 32)
          }

          if let playText = model.playText {
            Text(playText)
              .lineLimit(1)
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
      .accessibilityLabel("Play")
      .accessibilityValue(model.playText ?? "")

      Spacer(minLength: 0)

      Menu {
        PodcastEpisodeContextMenu(model: model.contextMenu)
      } label: {
        Image(systemName: "ellipsis")
          .font(.body)
          .fontWeight(.semibold)
          .foregroundStyle(.white.opacity(0.8))
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .menuOrder(.priority)
      .accessibilityLabel("More")
    }
  }
}

extension EpisodeCard {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let podcastID: String
    let title: String
    let coverURL: URL?
    let summary: String?
    let publishedAt: Date?
    let duration: Double?
    var progress: Double
    var backgroundColor: Color?
    let contextMenu: PodcastEpisodeContextMenu.Model

    var playText: String? {
      if progress >= 1 {
        return String(localized: "Played")
      }
      guard let duration, duration > 0 else {
        return nil
      }
      return Duration.seconds(duration * (1 - progress)).formatted(
        .units(allowed: [.hours, .minutes], width: .narrow)
      )
    }

    func onPlayTapped() {}

    init(
      id: String,
      podcastID: String,
      title: String,
      coverURL: URL? = nil,
      summary: String? = nil,
      publishedAt: Date? = nil,
      duration: Double? = nil,
      progress: Double = 0,
      backgroundColor: Color? = nil,
      contextMenu: PodcastEpisodeContextMenu.Model = .init(downloadState: .notDownloaded, actions: [])
    ) {
      self.id = id
      self.podcastID = podcastID
      self.title = title
      self.coverURL = coverURL
      self.summary = summary
      self.publishedAt = publishedAt
      self.duration = duration
      self.progress = progress
      self.backgroundColor = backgroundColor
      self.contextMenu = contextMenu
    }
  }
}

#Preview {
  NavigationStack {
    EpisodeCard(
      model: EpisodeCard.Model(
        id: "episode",
        podcastID: "podcast",
        title: "The 'But China!' Dilemma Driving the A.I. Race",
        coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        summary: "America is waking up to the critical risks posed by artificial intelligence.",
        publishedAt: Date(),
        duration: 3420,
        progress: 0.2,
        backgroundColor: Color(hue: 0.6, saturation: 0.2, brightness: 0.3)
      )
    )
    .padding()
  }
}
