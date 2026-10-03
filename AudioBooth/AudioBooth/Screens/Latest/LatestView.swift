import API
import Combine
import SwiftUI

struct LatestView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      content
        .background(theme.colors.background.page)
        .navigationTitle("Latest")
        .navigationDestinations()
        .refreshable {
          await model.refresh()
        }
        .onAppear(perform: model.onAppear)
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading && model.episodes.isEmpty {
      ProgressView("Loading...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.episodes.isEmpty {
      ContentUnavailableView(
        "No Recent Episodes",
        systemImage: "waveform",
        description: Text("Recent podcast episodes will appear here.")
      )
    } else {
      episodeList
    }
  }

  private var episodeList: some View {
    List(model.episodes) { episode in
      let menu = episode.contextMenu
      let canAddToQueue = menu?.actions.contains(.addToQueue) == true
      let canMarkAsFinished = menu?.actions.contains(.markAsFinished) == true
      let selector = menu?.collectionSelector

      NavigationLink(value: NavigationDestination.podcast(id: episode.podcastID, episodeID: episode.id)) {
        episodeRow(episode)
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      .swipeActions(edge: .leading) {
        if let menu, canAddToQueue {
          Button(action: menu.onAddToQueueTapped) {
            Label("Add to Queue", systemImage: "text.badge.plus")
          }
          .tint(.accentColor)
        }
      }
      .swipeActions(edge: .trailing) {
        if let menu, canMarkAsFinished {
          Button(action: menu.onMarkAsFinishedTapped) {
            Label("Mark as Finished", systemImage: "checkmark.shield")
          }
          .tint(.green)
        }
      }
      .contextMenu {
        if let menu {
          PodcastEpisodeContextMenu(model: menu)
        }
      }
      .menuOrder(.priority)
      .podcastEpisodeAccessibilityActions(episodeID: episode.id, menu: menu)
      .sheet(
        item: Binding(
          get: { selector },
          set: { menu?.collectionSelector = $0 }
        )
      ) { sheetModel in
        CollectionSelectorSheet(model: sheetModel)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func episodeRow(_ episode: Model.Episode) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 8) {
        Cover(
          model: Cover.Model(url: episode.coverURL),
          style: .plain
        )
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        playButton(episode)
      }
      .frame(width: 72)

      VStack(alignment: .leading, spacing: 4) {
        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        if let publishedAt = episode.publishedAt {
          Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if let summary = episode.summary, !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  private func playButton(_ episode: Model.Episode) -> some View {
    let isCurrentEpisode = episode.id == model.currentEpisodeID
    let isCurrentlyPlaying = isCurrentEpisode && model.isPlaying
    let isCurrentlyLoading = isCurrentEpisode && model.isPlayerLoading

    return Button {
      model.onPlayTapped(episode)
    } label: {
      HStack(spacing: 6) {
        if isCurrentlyLoading {
          ProgressView()
            .controlSize(.mini)
        } else {
          Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
        }

        if let playText = episode.playText {
          Text(playText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.black)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        playButtonBackground(progress: episode.progress)
      }
      .clipShape(.capsule)
    }
    .buttonStyle(.borderless)
    .disabled(isCurrentlyLoading)
    .accessibilityLabel(isCurrentlyPlaying ? "Pause" : "Play")
    .accessibilityValue(episode.playText ?? "")
  }

  @ViewBuilder
  private func playButtonBackground(progress: Double) -> some View {
    if progress >= 0.01 {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Color(white: 0.85)

          Rectangle()
            .fill(.white)
            .frame(width: geometry.size.width * min(progress, 1))
        }
      }
    } else {
      Color.white
    }
  }
}

extension LatestView {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var episodes: [Episode]
    var currentEpisodeID: String?
    var isPlaying: Bool
    var isPlayerLoading: Bool

    func onAppear() {}
    func refresh() async {}
    func onPlayTapped(_ episode: Episode) {}

    init(
      isLoading: Bool = false,
      episodes: [Episode] = [],
      currentEpisodeID: String? = nil,
      isPlaying: Bool = false,
      isPlayerLoading: Bool = false
    ) {
      self.isLoading = isLoading
      self.episodes = episodes
      self.currentEpisodeID = currentEpisodeID
      self.isPlaying = isPlaying
      self.isPlayerLoading = isPlayerLoading
    }
  }
}

extension LatestView.Model {
  struct Episode: Identifiable {
    let id: String
    let podcastID: String
    let podcastTitle: String
    let title: String
    let coverURL: URL?
    let publishedAt: Date?
    let duration: Double?
    var progress: Double
    let summary: String?
    let contextMenu: PodcastEpisodeContextMenu.Model?

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
  }
}

#Preview {
  LatestView(model: .init())
}
