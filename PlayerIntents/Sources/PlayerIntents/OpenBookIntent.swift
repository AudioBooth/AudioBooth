import AppIntents
import Foundation

public struct OpenBookIntent: AudioPlaybackIntent {
  public static let title: LocalizedStringResource = "Open audiobook"
  public static let description = IntentDescription("Opens a specific audiobook.")
  public static let openAppWhenRun = true

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
    await playerManager.open(bookID)
    return .result()
  }
}
