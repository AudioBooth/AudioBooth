import Foundation

/// A physical gesture on a connected headphone / remote that maps to the
/// media "next track" and "previous track" commands.
public enum HeadphoneGesture: String, Sendable, CaseIterable {
  case previous
  case next
}

/// The concrete playback command that should run for a headphone gesture,
/// once the user's preference and the current playback context have been
/// resolved. This is intentionally free of any UIKit / player dependencies so
/// the routing logic can be unit tested in isolation.
public enum HeadphoneCommand: String, Sendable, Equatable, CaseIterable {
  case skipForward
  case skipBackward
  case nextChapter
  case previousChapter
  case addBookmark
  case none
}

/// A user-configurable action that can be bound to a headphone gesture.
///
/// The raw values are persisted via `@AppStorage`, so they must remain stable.
public enum HeadphoneAction: String, Sendable, CaseIterable, Identifiable {
  /// Preserve the app's built-in behavior (skip by seconds, or by chapter when
  /// the "skip by chapters" lock-screen preference is enabled).
  case `default`
  case skipForward
  /// Skip backward by the configured interval. Presented as "Rewind".
  case rewind
  case nextChapter
  case previousChapter
  case addBookmark
  case none

  public var id: String { rawValue }

  public var displayText: LocalizedStringResource {
    switch self {
    case .default: "Default"
    case .skipForward: "Skip Forward"
    case .rewind: "Rewind"
    case .nextChapter: "Next Chapter"
    case .previousChapter: "Previous Chapter"
    case .addBookmark: "Add Bookmark"
    case .none: "Nothing"
    }
  }

  public var systemImage: String {
    switch self {
    case .default: "gearshape"
    case .skipForward: "goforward"
    case .rewind: "gobackward"
    case .nextChapter: "forward.end.fill"
    case .previousChapter: "backward.end.fill"
    case .addBookmark: "bookmark.fill"
    case .none: "nosign"
    }
  }

  /// The default action for a gesture when no override has been chosen yet.
  public static func defaultAction(for gesture: HeadphoneGesture) -> HeadphoneAction {
    .default
  }
}

/// Pure resolver that turns a configured ``HeadphoneAction`` into the concrete
/// ``HeadphoneCommand`` to execute, taking the current playback context into
/// account. Kept dependency-free so it is fully unit testable.
public enum HeadphoneActionResolver {
  /// - Parameters:
  ///   - action: The user's configured action for the gesture.
  ///   - gesture: Which physical gesture was performed.
  ///   - usesChapters: Whether the "skip by chapters" preference is enabled
  ///     (only relevant for ``HeadphoneAction/default``).
  ///   - hasChapters: Whether the currently playing item exposes chapters.
  public static func resolve(
    action: HeadphoneAction,
    gesture: HeadphoneGesture,
    usesChapters: Bool,
    hasChapters: Bool
  ) -> HeadphoneCommand {
    switch action {
    case .default:
      switch gesture {
      case .next:
        return (usesChapters && hasChapters) ? .nextChapter : .skipForward
      case .previous:
        return (usesChapters && hasChapters) ? .previousChapter : .skipBackward
      }

    case .skipForward:
      return .skipForward

    case .rewind:
      return .skipBackward

    case .nextChapter:
      // Fall back to a plain skip when the item has no chapters to move between.
      return hasChapters ? .nextChapter : .skipForward

    case .previousChapter:
      return hasChapters ? .previousChapter : .skipBackward

    case .addBookmark:
      return .addBookmark

    case .none:
      return .none
    }
  }
}
