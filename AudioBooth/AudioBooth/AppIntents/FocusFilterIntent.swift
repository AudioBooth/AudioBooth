import AppIntents
import Foundation

struct FocusFilterIntent: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Focus Features"

  @Parameter(title: "Start Sleep Timer")
  var startSleepTimer: Bool?

  private var isEnabled: Bool { startSleepTimer == true }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "Focus Features",
      subtitle: isEnabled ? "Sleep timer on" : "Sleep timer off"
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
      return filter?.isEnabled ?? false
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard isEnabled,
      UserPreferences.shared.autoTimerTrigger != .timeWindow,
      let playerModel = PlayerManager.shared.current,
      let timer = playerModel.timer as? TimerPickerSheetViewModel
    else {
      return .result()
    }

    timer.activateFocusTimer()
    return .result()
  }
}
