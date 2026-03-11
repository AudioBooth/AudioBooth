import API
import Foundation
import Models

final class StatsPageViewModel: StatsPageView.Model {
  private let preferences = UserPreferences.shared

  init() {
    super.init(isLoading: true, dailyGoalMinutes: UserPreferences.shared.dailyGoalMinutes)
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

  override func onGoalChanged(_ minutes: Int) {
    dailyGoalMinutes = minutes
    preferences.dailyGoalMinutes = minutes
  }

  private func processStats(_ stats: ListeningStats) async {
    totalTime = stats.totalTime
    todayTime = stats.today

    daysListened = stats.days.values.filter { $0 > 0 }.count

    do {
      let allProgress = try MediaProgress.fetchAll()
      itemsFinished = allProgress.filter { $0.isFinished }.count
    } catch {
      itemsFinished = 0
    }

    if let sessions = stats.recentSessions {
      recentSessions = sessions.map { session in
        StatsPageView.Model.SessionData(
          id: session.id,
          title: session.displayTitle,
          timeListening: session.timeListening ?? 0,
          updatedAt: session.updatedAt
        )
      }
    }

    listeningDays = stats.days

    isLoading = false
  }
}
