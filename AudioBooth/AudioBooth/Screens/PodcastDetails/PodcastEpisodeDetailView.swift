import RichText
import SwiftUI

struct PodcastEpisodeDetailView: View {
  let model: Model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header

        if let description = model.description {
          descriptionSection(description)
        }

        if !model.chapters.isEmpty {
          chaptersSection
        }
      }
      .padding()
    }
    .navigationTitle(model.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let episodeLabel = model.episodeLabel {
        Text(episodeLabel)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Text(model.title)
        .font(.title2)
        .fontWeight(.bold)

      HStack(spacing: 12) {
        if let publishedAt = model.publishedAt {
          Label(
            publishedAt.formatted(date: .abbreviated, time: .omitted),
            systemImage: "calendar"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if let durationText = model.durationText {
          Label(durationText, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func descriptionSection(_ description: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Description")
        .font(.headline)

      RichText(
        html: description,
        configuration: Configuration(
          customCSS: "body { font: -apple-system-subheadline; }"
        )
      )
      .allowsHitTesting(false)
    }
    .textSelection(.enabled)
  }

  private var chaptersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Chapters")
        .font(.headline)

      ForEach(model.chapters) { chapter in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(chapter.title)
              .font(.subheadline)

            Text(chapter.startText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Text(chapter.durationText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)

        if chapter.id != model.chapters.last?.id {
          Divider()
        }
      }
    }
  }
}

extension PodcastEpisodeDetailView {
  struct Model {
    let title: String
    let description: String?
    let publishedAt: Date?
    let duration: Double?
    let season: String?
    let episode: String?
    let chapters: [PodcastDetailsView.Model.Chapter]

    var episodeLabel: String? {
      if let season, !season.isEmpty, let episode, !episode.isEmpty {
        return "Season \(season), Episode \(episode)"
      } else if let episode, !episode.isEmpty {
        return "Episode \(episode)"
      }
      return nil
    }

    var durationText: String? {
      guard let duration, duration > 0 else { return nil }
      return Duration.seconds(duration).formatted(
        .units(
          allowed: [.hours, .minutes],
          width: .narrow
        )
      )
    }

    init(episode: PodcastDetailsView.Model.Episode) {
      self.title = episode.title
      self.description = episode.description?.replacingOccurrences(of: "\n", with: "<br>")
      self.publishedAt = episode.publishedAt
      self.duration = episode.duration
      self.season = episode.season
      self.episode = episode.episode
      self.chapters = episode.chapters
    }

    init(
      title: String,
      description: String? = nil,
      publishedAt: Date? = nil,
      duration: Double? = nil,
      season: String? = nil,
      episode: String? = nil,
      chapters: [PodcastDetailsView.Model.Chapter] = []
    ) {
      self.title = title
      self.description = description
      self.publishedAt = publishedAt
      self.duration = duration
      self.season = season
      self.episode = episode
      self.chapters = chapters
    }
  }
}

#Preview {
  NavigationStack {
    PodcastEpisodeDetailView(
      model: .init(
        title: "The Sunday Read: 'The Untold Story'",
        description:
          "A deep dive into an untold story that captivated the world. This episode explores the hidden details behind one of the most significant events of the year.",
        publishedAt: Date(),
        duration: 1800,
        season: "1",
        episode: "5",
        chapters: [
          .init(id: 0, start: 0, end: 600, title: "Introduction"),
          .init(id: 1, start: 600, end: 1200, title: "The Discovery"),
          .init(id: 2, start: 1200, end: 1800, title: "Conclusion"),
        ]
      )
    )
  }
}
