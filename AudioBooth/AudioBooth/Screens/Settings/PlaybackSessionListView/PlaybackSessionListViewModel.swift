import Foundation
import Models
import OSLog

@MainActor
final class PlaybackSessionListViewModel: PlaybackSessionListView.Model {
  init() {
    super.init(sessions: [])
  }

  override func onAppear() {
    loadSessions()
  }

  private func loadSessions() {
    do {
      sessions = try PlaybackSession.fetchAll()
    } catch {
      AppLogger.viewModel.error(
        "Failed to fetch playback sessions: \(error.localizedDescription, privacy: .public)")
      sessions = []
    }
  }
}
