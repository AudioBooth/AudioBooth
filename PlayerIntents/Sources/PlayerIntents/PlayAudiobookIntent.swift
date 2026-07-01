import AppIntents
import Foundation

@available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@AppIntent(schema: .books.playAudiobook)
public struct PlayAudiobookIntent: AudioPlaybackIntent {
  @Dependency
  private var playerManager: PlayerManagerProtocol

  @Parameter(optionsProvider: AudiobookEntityOptionsProvider())
  public var target: AudiobookEntity

  public init() {}

  public func perform() async throws -> some IntentResult {
    await playerManager.play(target.id)
    return .result()
  }
}
