import API
import Combine
import SwiftUI

struct PodcastFeedView: View {
  @Environment(\.appTheme) var theme

  private let audiobookshelf = Audiobookshelf.shared

  @StateObject var model: Model

  var body: some View {
    Group {
      if model.isLoading && model.episodes.isEmpty {
        ProgressView("Loading episodes...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = model.error, model.episodes.isEmpty {
        ContentUnavailableView {
          Label("Unable to Load Feed", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again") {
            model.onAppear()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        content
      }
    }
    .background(theme.colors.background.page)
    .navigationTitle("Find Episodes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          model.onToggleSort()
        } label: {
          Label(
            "Sort",
            systemImage: model.sortDescending ? "chevron.down" : "chevron.up"
          )
        }
        .tint(.primary)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private var content: some View {
    VStack(spacing: 0) {
      TextField("Search episodes", text: $model.searchText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)
        .padding(.vertical, 8)

      ScrollView {
        LazyVStack(spacing: 0) {
          countHeader

          ForEach(model.filteredEpisodes) { episode in
            row(episode)
              .padding(.horizontal)
            Divider()
          }
        }
        .padding(.bottom)
      }
    }
  }

  private var countHeader: some View {
    HStack {
      Text(model.countText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  private func row(_ episode: Model.Episode) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        HStack(spacing: 8) {
          if let publishedAt = episode.publishedAt {
            Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let durationText = episode.durationText {
            Text(verbatim: "•")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(durationText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let description = episode.descriptionPlain, !description.isEmpty {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }

        actionButton(episode)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func actionButton(_ episode: Model.Episode) -> some View {
    switch episode.state {
    case .onServer:
      label(text: "Available", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.secondary)
    case .requested:
      label(text: "Requested", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case .remote:
      if let userType = audiobookshelf.authentication.server?.userType,
        [.root, .admin].contains(userType)
      {
        Button {
          model.onRequestDownload(episode)
        } label: {
          label(text: "Request Download", systemImage: "icloud.and.arrow.down")
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      } else {
        label(text: "Not on server", systemImage: "icloud.slash")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func label(text: String, systemImage: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: systemImage)
    }
    .font(.caption)
    .fontWeight(.medium)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}

// MARK: - Model

extension PodcastFeedView {
  @Observable
  class Model: ObservableObject {
    let podcastID: String
    let podcastTitle: String
    let coverURL: URL?
    let feedURL: String

    var isLoading: Bool
    var error: String?
    var episodes: [Episode]
    var searchText: String
    var sortDescending: Bool

    var filteredEpisodes: [Episode] {
      var result = episodes

      if !searchText.isEmpty {
        let query = searchText.lowercased()
        result = result.filter {
          $0.title.lowercased().contains(query)
            || ($0.descriptionPlain?.lowercased().contains(query) ?? false)
        }
      }

      result.sort {
        let a = $0.publishedAt ?? .distantPast
        let b = $1.publishedAt ?? .distantPast
        return sortDescending ? a > b : a < b
      }

      return result
    }

    var countText: String {
      let filtered = filteredEpisodes.count
      let total = episodes.count
      if filtered == total {
        return "\(total) Episodes"
      } else {
        return "\(filtered) of \(total) Episodes"
      }
    }

    func onAppear() {}
    func onToggleSort() { sortDescending.toggle() }
    func onRequestDownload(_ episode: Episode) {}

    init(
      podcastID: String,
      podcastTitle: String,
      coverURL: URL?,
      feedURL: String,
      isLoading: Bool = true,
      error: String? = nil,
      episodes: [Episode] = [],
      searchText: String = "",
      sortDescending: Bool = true
    ) {
      self.podcastID = podcastID
      self.podcastTitle = podcastTitle
      self.coverURL = coverURL
      self.feedURL = feedURL
      self.isLoading = isLoading
      self.error = error
      self.episodes = episodes
      self.searchText = searchText
      self.sortDescending = sortDescending
    }
  }
}

extension PodcastFeedView.Model {
  struct Episode: Identifiable {
    let id: String
    let title: String
    let descriptionPlain: String?
    let publishedAt: Date?
    let durationSeconds: Double?
    var state: State
    var feedEpisode: Podcast.Feed.Episode

    enum State {
      case remote
      case requested
      case onServer
    }

    var durationText: String? {
      guard let durationSeconds, durationSeconds > 0 else { return nil }
      return Duration.seconds(durationSeconds).formatted(
        .units(allowed: [.hours, .minutes], width: .narrow)
      )
    }
  }
}
