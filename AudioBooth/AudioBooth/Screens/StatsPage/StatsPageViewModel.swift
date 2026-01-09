import API
import Foundation
import Models

final class StatsPageViewModel: StatsPageView.Model {
  init() {
    super.init(isLoading: true)
  }

  override func onAppear() {
    Task {
      await fetchStats()
    }
  }

  private func fetchStats() async {
    do {
      let stats = try await Audiobookshelf.shared.authentication.fetchListeningStats()
      await processStats(stats)
    } catch {
      isLoading = false
    }
  }

  private func processStats(_ stats: ListeningStats) async {
    totalTime = stats.totalTime

    daysListened = stats.days.values.filter { $0 > 0 }.count

    do {
      let allProgress = try await MediaProgress.fetchAll()
      itemsFinished = allProgress.filter { $0.isFinished }.count
    } catch {
      itemsFinished = 0
    }

    if let sessions = stats.recentSessions {
      recentSessions = sessions.map { session in
        StatsPageView.Model.SessionData(
          id: session.id,
          title: session.displayTitle,
          timeListening: session.timeListening,
          updatedAt: session.updatedAt
        )
      }
    }

    isLoading = false
  }
}
