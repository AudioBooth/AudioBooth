import AppIntents
import Foundation

/// A snapshot of whatever is currently playing, returned by
/// ``GetCurrentItemIntent`` so Shortcuts can read the title, author, chapter and
/// playback position.
struct NowPlayingItemEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Now Playing Item"
  static let defaultQuery = NowPlayingItemQuery()

  /// The identifier of the playing book / episode.
  let id: String

  @Property(title: "Title")
  var title: String

  @Property(title: "Author")
  var author: String?

  @Property(title: "Chapter")
  var chapterTitle: String?

  /// Current playback position, in seconds.
  @Property(title: "Current Time")
  var currentTime: Double

  /// Total duration, in seconds.
  @Property(title: "Duration")
  var duration: Double

  /// Progress through the item, from 0 to 1.
  @Property(title: "Progress")
  var progress: Double

  /// Human-readable position, e.g. "1:23:45".
  @Property(title: "Position")
  var positionText: String

  init(
    id: String,
    title: String,
    author: String?,
    chapterTitle: String?,
    currentTime: Double,
    duration: Double,
    progress: Double,
    positionText: String
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.chapterTitle = chapterTitle
    self.currentTime = currentTime
    self.duration = duration
    self.progress = progress
    self.positionText = positionText
  }

  var displayRepresentation: DisplayRepresentation {
    var subtitleParts: [String] = []
    if let author { subtitleParts.append(author) }
    if let chapterTitle { subtitleParts.append(chapterTitle) }

    return DisplayRepresentation(
      title: "\(title)",
      subtitle: subtitleParts.isEmpty ? nil : "\(subtitleParts.joined(separator: " · "))"
    )
  }
}

/// The now playing item is ephemeral, so the query only ever resolves the single
/// item that is currently loaded in the player.
struct NowPlayingItemQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [String]) async throws -> [NowPlayingItemEntity] {
    guard
      let entity = NowPlayingItemEntity.current(),
      identifiers.contains(entity.id)
    else { return [] }
    return [entity]
  }

  @MainActor
  func suggestedEntities() async throws -> [NowPlayingItemEntity] {
    NowPlayingItemEntity.current().map { [$0] } ?? []
  }
}

extension NowPlayingItemEntity {
  /// Builds an entity from the player's current state, or `nil` if nothing is
  /// playing.
  @MainActor
  static func current() -> NowPlayingItemEntity? {
    guard let current = PlayerManager.shared.current as? BookPlayerModel else {
      return nil
    }

    let currentTime = Double(current.getCurrentTime() ?? 0)
    let duration = current.playbackProgress.total
    let progress = duration > 0 ? min(1, max(0, currentTime / duration)) : 0

    return NowPlayingItemEntity(
      id: current.id,
      title: current.title,
      author: current.author,
      chapterTitle: current.chapters?.current?.title,
      currentTime: currentTime,
      duration: duration,
      progress: progress,
      positionText: Self.positionString(from: currentTime)
    )
  }

  private static func positionString(from seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }
}
