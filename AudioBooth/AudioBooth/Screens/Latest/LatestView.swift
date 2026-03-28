import API
import Combine
import SwiftUI

struct LatestView: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Latest")
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
          case .podcast(let id, let episodeID):
            PodcastDetailsView(model: PodcastDetailsViewModel(podcastID: id, episodeID: episodeID))
          default:
            EmptyView()
          }
        }
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
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(model.episodes) { episode in
          NavigationLink(value: NavigationDestination.podcast(id: episode.podcastID, episodeID: episode.id)) {
            episodeRow(episode)
              .padding(.horizontal)
          }
          .buttonStyle(.plain)
          Divider()
            .padding(.leading)
        }
      }
    }
  }

  private func episodeRow(_ episode: Model.Episode) -> some View {
    HStack(spacing: 12) {
      Cover(
        model: Cover.Model(url: episode.coverURL),
        style: .plain
      )
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        HStack(spacing: 8) {
          if let publishedAt = episode.publishedAt {
            Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

          if let durationText = episode.durationText {
            Text(durationText)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

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
}

extension LatestView {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var episodes: [Episode]

    func onAppear() {}
    func refresh() async {}

    init(
      isLoading: Bool = false,
      episodes: [Episode] = []
    ) {
      self.isLoading = isLoading
      self.episodes = episodes
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
    let progress: Double

    var durationText: String? {
      guard let duration, duration > 0 else { return nil }
      return Duration.seconds(duration).formatted(
        .units(allowed: [.hours, .minutes], width: .narrow)
      )
    }
  }
}

#Preview {
  LatestView(model: .init())
}
