import AppIntents
import Foundation

struct FocusFilterIntent: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Auto Sleep"
  static let description = IntentDescription(
    "Automatically starts a sleep timer while this Focus is on."
  )

  @Parameter(title: "Start Sleep Timer", default: false)
  var startSleepTimer: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "Auto Sleep",
      subtitle: startSleepTimer ? "Sleep timer on" : "Sleep timer off"
    )
  }

  static func suggestedFocusFilters(
    for context: FocusFilterSuggestionContext
  ) async -> [FocusFilterIntent] {
    let suggestion = FocusFilterIntent()
    suggestion.startSleepTimer = true
    return [suggestion]
  }

  static var isActive: Bool {
    get async {
      let filter = try? await Self.current
      return filter?.startSleepTimer ?? false
    }
  }

  func perform() async throws -> some IntentResult {
    guard startSleepTimer,
      UserPreferences.shared.autoTimerTrigger.includesFocus,
      let playerModel = PlayerManager.shared.current,
      let timer = playerModel.timer as? TimerPickerSheetViewModel
    else {
      return .result()
    }

    timer.activateFocusTimer()
    return .result()
  }
}
