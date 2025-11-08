import AppIntents
import Foundation

public struct PausePlaybackIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Pause playback"
  public static let description = IntentDescription("Pauses the currently playing audiobook.")
  public static let openAppWhenRun = false

  @Dependency
  private var playerManager: PlayerManagerProtocol

  public init() {}

  public func perform() async throws -> some IntentResult {
    await MainActor.run {
      playerManager.pause()
    }

    return .result()
  }
}
