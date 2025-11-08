import AppIntents
import Foundation

public struct ResumePlaybackIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Resume last played audiobook"
  public static let description = IntentDescription("Resumes the last played audiobook.")
  public static let openAppWhenRun = false

  @Dependency
  private var playerManager: PlayerManagerProtocol

  public init() {}

  public func perform() async throws -> some IntentResult {
    await MainActor.run {
      playerManager.play()
    }

    return .result()
  }
}
