import AppIntents
import Foundation

public struct PlayBookIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Play audiobook"
  public static let description = IntentDescription("Plays a specific audiobook.")
  public static let openAppWhenRun = false
  public static let isDiscoverable = false

  @Dependency
  private var playerManager: PlayerManagerProtocol

  @Parameter(title: "Book ID")
  public var bookID: String

  public init() {
    bookID = ""
  }

  public init(bookID: String) {
    self.bookID = bookID
  }

  public func perform() async throws -> some IntentResult {
    await playerManager.play(bookID)
    return .result()
  }
}
