import Foundation

public enum SortBy: String, Sendable {
  case title = "media.metadata.title"
  case authorName = "media.metadata.authorName"
  case authorNameLF = "media.metadata.authorNameLF"
  case author = "media.metadata.author"
  case publishedYear = "media.metadata.publishedYear"
  case addedAt
  case size
  case duration = "media.duration"
  case numEpisodes = "media.numTracks"
  case updatedAt
  case progress
  case progressFinishedAt = "progress.finishedAt"
  case progressCreatedAt = "progress.createdAt"
  case birthtime = "birthtimeMs"
  case modified = "mtimeMs"
  case random

  public static let bookOptions: [SortBy] = [
    .title,
    .authorName,
    .authorNameLF,
    .publishedYear,
    .addedAt,
    .size,
    .duration,
    .updatedAt,
    .birthtime,
    .modified,
    .progress,
    .progressFinishedAt,
    .progressCreatedAt,
    .random,
  ]

  public static let podcastOptions: [SortBy] = [
    .title,
    .author,
    .addedAt,
    .size,
    .numEpisodes,
    .birthtime,
    .modified,
    .random,
  ]
}
