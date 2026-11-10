import AppIntents
import Foundation

struct AddBookmarkIntent: AppIntent {
  static let title: LocalizedStringResource = "Add a bookmark"
  static let description = IntentDescription(
    "Adds a bookmark at the current position in the playing audiobook."
  )
  static let openAppWhenRun = false

  @Parameter(
    title: "Content",
    description: "The bookmark title",
    requestValueDialog: "What should the bookmark be called?"
  )
  var content: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Add bookmark \(\.$content)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let bookTitle = try await MainActor.run {
      guard let player = PlayerManager.shared.current as? BookPlayerModel,
        player.book.podcastID == nil,
        let bookmarks = player.options.bookmarks as? BookBookmarksModel
      else {
        throw AppIntentError.noAudiobookPlaying
      }

      guard bookmarks.addBookmark(title: content?.isEmpty == false ? content : nil) else {
        throw AppIntentError.bookmarkAlreadyExists
      }

      return player.title
    }

    return .result(dialog: "Bookmark added to \(bookTitle)")
  }
}
