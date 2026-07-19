import AppIntents
import Foundation

struct GetCurrentItemIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Current Item"
  static let description = IntentDescription(
    "Returns the audiobook or podcast that is currently playing, including its position and chapter."
  )
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ReturnsValue<NowPlayingItemEntity> & ProvidesDialog {
    let entity = try await MainActor.run {
      guard let entity = NowPlayingItemEntity.current() else {
        throw AppIntentError.noAudiobookPlaying
      }
      return entity
    }

    let dialog: IntentDialog
    if let chapter = entity.chapterTitle {
      dialog = "Playing \(entity.title) — \(chapter), \(entity.positionText) in."
    } else {
      dialog = "Playing \(entity.title), \(entity.positionText) in."
    }

    return .result(value: entity, dialog: dialog)
  }
}
