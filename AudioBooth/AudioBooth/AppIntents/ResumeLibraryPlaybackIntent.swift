import AppIntents
import Foundation

struct ResumeLibraryPlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume last played in library"
  static let description = IntentDescription("Resumes the last item played in a specific library.")
  static let openAppWhenRun = false

  static var parameterSummary: some ParameterSummary {
    Summary("Resume last played in \(\.$library)")
  }

  @Parameter(title: "Library")
  var library: ResumeLibraryEntity

  init() {}

  func perform() async throws -> some IntentResult {
    try await PlayerManager.shared.resumeLastPlayed(in: library.id)
    return .result()
  }
}

enum ResumePlaybackError: Error, CustomLocalizedStringResourceConvertible {
  case nothingPlayed
  case couldNotStart

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .nothingPlayed: "Nothing played in this library yet."
    case .couldNotStart: "Couldn't start playback."
    }
  }
}
