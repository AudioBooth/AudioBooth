import Foundation
import Testing

@testable import Models

@Suite("HeadphoneAction raw values")
struct HeadphoneActionRawValueTests {
  @Test("Every case round-trips through its persisted raw value")
  func rawValueRoundTrip() {
    for action in HeadphoneAction.allCases {
      let restored = HeadphoneAction(rawValue: action.rawValue)
      #expect(restored == action)
    }
  }

  @Test("Persisted raw values are stable")
  func stableRawValues() {
    // These strings are written to @AppStorage and must not change, or existing
    // users' saved preferences would silently reset.
    #expect(HeadphoneAction.default.rawValue == "default")
    #expect(HeadphoneAction.skipForward.rawValue == "skipForward")
    #expect(HeadphoneAction.rewind.rawValue == "rewind")
    #expect(HeadphoneAction.nextChapter.rawValue == "nextChapter")
    #expect(HeadphoneAction.previousChapter.rawValue == "previousChapter")
    #expect(HeadphoneAction.addBookmark.rawValue == "addBookmark")
    #expect(HeadphoneAction.none.rawValue == "none")
  }

  @Test("An unknown raw value does not resolve to a case")
  func unknownRawValue() {
    #expect(HeadphoneAction(rawValue: "totally-unknown") == nil)
  }

  @Test("Both gestures default to .default")
  func defaultActions() {
    #expect(HeadphoneAction.defaultAction(for: .next) == .default)
    #expect(HeadphoneAction.defaultAction(for: .previous) == .default)
  }
}

@Suite("HeadphoneActionResolver")
struct HeadphoneActionResolverTests {
  // MARK: - Default action preserves built-in behavior

  @Test("Default next skips forward when not using chapters")
  func defaultNextSeconds() {
    let command = HeadphoneActionResolver.resolve(
      action: .default,
      gesture: .next,
      usesChapters: false,
      hasChapters: true
    )
    #expect(command == .skipForward)
  }

  @Test("Default next moves to next chapter when using chapters and chapters exist")
  func defaultNextChapters() {
    let command = HeadphoneActionResolver.resolve(
      action: .default,
      gesture: .next,
      usesChapters: true,
      hasChapters: true
    )
    #expect(command == .nextChapter)
  }

  @Test("Default next falls back to skip when chapters preference is on but item has none")
  func defaultNextChaptersButNoneAvailable() {
    let command = HeadphoneActionResolver.resolve(
      action: .default,
      gesture: .next,
      usesChapters: true,
      hasChapters: false
    )
    #expect(command == .skipForward)
  }

  @Test("Default previous skips backward when not using chapters")
  func defaultPreviousSeconds() {
    let command = HeadphoneActionResolver.resolve(
      action: .default,
      gesture: .previous,
      usesChapters: false,
      hasChapters: true
    )
    #expect(command == .skipBackward)
  }

  @Test("Default previous moves to previous chapter when using chapters and chapters exist")
  func defaultPreviousChapters() {
    let command = HeadphoneActionResolver.resolve(
      action: .default,
      gesture: .previous,
      usesChapters: true,
      hasChapters: true
    )
    #expect(command == .previousChapter)
  }

  // MARK: - Explicit overrides ignore the gesture direction

  @Test("Add Bookmark resolves regardless of gesture or context", arguments: HeadphoneGesture.allCases)
  func addBookmarkAlways(gesture: HeadphoneGesture) {
    let command = HeadphoneActionResolver.resolve(
      action: .addBookmark,
      gesture: gesture,
      usesChapters: Bool.random(),
      hasChapters: Bool.random()
    )
    #expect(command == .addBookmark)
  }

  @Test("Skip Forward override always skips forward even on the previous gesture")
  func skipForwardOverrideOnPrevious() {
    let command = HeadphoneActionResolver.resolve(
      action: .skipForward,
      gesture: .previous,
      usesChapters: true,
      hasChapters: true
    )
    #expect(command == .skipForward)
  }

  @Test("Rewind override always skips backward even on the next gesture")
  func rewindOverrideOnNext() {
    let command = HeadphoneActionResolver.resolve(
      action: .rewind,
      gesture: .next,
      usesChapters: false,
      hasChapters: false
    )
    #expect(command == .skipBackward)
  }

  @Test("None override is a no-op for both gestures", arguments: HeadphoneGesture.allCases)
  func noneOverride(gesture: HeadphoneGesture) {
    let command = HeadphoneActionResolver.resolve(
      action: .none,
      gesture: gesture,
      usesChapters: false,
      hasChapters: true
    )
    #expect(command == HeadphoneCommand.none)
  }

  // MARK: - Chapter overrides fall back when no chapters exist

  @Test("Next Chapter override falls back to skip forward when the item has no chapters")
  func nextChapterFallback() {
    #expect(
      HeadphoneActionResolver.resolve(
        action: .nextChapter,
        gesture: .next,
        usesChapters: false,
        hasChapters: false
      ) == .skipForward
    )
    #expect(
      HeadphoneActionResolver.resolve(
        action: .nextChapter,
        gesture: .next,
        usesChapters: false,
        hasChapters: true
      ) == .nextChapter
    )
  }

  @Test("Previous Chapter override falls back to skip backward when the item has no chapters")
  func previousChapterFallback() {
    #expect(
      HeadphoneActionResolver.resolve(
        action: .previousChapter,
        gesture: .previous,
        usesChapters: false,
        hasChapters: false
      ) == .skipBackward
    )
    #expect(
      HeadphoneActionResolver.resolve(
        action: .previousChapter,
        gesture: .previous,
        usesChapters: false,
        hasChapters: true
      ) == .previousChapter
    )
  }
}
