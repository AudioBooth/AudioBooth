import API
import Combine
import Foundation
import Models
import UIKit
import WidgetKit

final class ListeningStatsCardModel: ListeningStatsCard.Model {
  private var cancellables = Set<AnyCancellable>()

  init() {
    super.init(isLoading: true)

    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        Task {
          await self?.fetchStats()
        }
      }
      .store(in: &cancellables)
  }

  override func onAppear() {
    Task {
      isLoading = true
      await fetchStats()
    }
  }

  private func fetchStats() async {
    do {
      let stats = try await Audiobookshelf.shared.authentication.fetchListeningStats()
      processStats(stats)
    } catch {
      isLoading = false
    }
  }

  private func processStats(_ stats: ListeningStats) {
    todayTime = stats.today
    weekData = calculateWeekData(stats.days)

    let weekTotal = weekData.reduce(0) { $0 + $1.timeInSeconds }
    totalTime = weekTotal

    daysInARow = calculateDaysInARow(stats.days)

    isLoading = false

    syncWidgetStats(stats)
  }

  private func syncWidgetStats(_ stats: ListeningStats) {
    let widgetWeekData = weekData.map {
      WidgetStatsData.DayEntry(date: $0.id, label: $0.label, timeInSeconds: $0.timeInSeconds)
    }

    let data = WidgetStatsData(
      todayTime: stats.today,
      dailyGoalMinutes: UserPreferences.shared.dailyGoalMinutes,
      weekData: widgetWeekData,
      days: stats.days,
      daysInARow: daysInARow
    )

    if let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS"),
      let encoded = try? JSONEncoder().encode(data)
    {
      sharedDefaults.set(encoded, forKey: "listeningStats")
      WidgetCenter.shared.reloadTimelines(ofKind: "DailyGoalWidget")
      WidgetCenter.shared.reloadTimelines(ofKind: "WeeklyListeningWidget")
      WidgetCenter.shared.reloadTimelines(ofKind: "ListeningActivityWidget")
    }
  }

  private func calculateWeekData(_ days: [String: Double]) -> [DayData] {
    let calendar = Calendar.current
    let today = Date()

    var weekDays: [DayData] = []
    var maxTime: Double = 0

    for i in (0..<7).reversed() {
      guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }

      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "yyyy-MM-dd"
      let dateString = dateFormatter.string(from: date)

      let timeInSeconds = days[dateString] ?? 0
      maxTime = max(maxTime, timeInSeconds)

      let dayLabel = calendar.component(.weekday, from: date)
      let label = calendar.shortWeekdaySymbols[dayLabel - 1]

      weekDays.append(
        DayData(
          id: dateString,
          label: label,
          timeInSeconds: timeInSeconds,
          normalizedValue: 0,
        )
      )
    }

    let normalizedDays = weekDays.map { day in
      let normalizedValue = maxTime > 0 ? day.timeInSeconds / maxTime : 0

      return DayData(
        id: day.id,
        label: day.label,
        timeInSeconds: day.timeInSeconds,
        normalizedValue: normalizedValue
      )
    }

    return normalizedDays
  }

  private func calculateDaysInARow(_ days: [String: Double]) -> Int {
    let calendar = Calendar.current
    let today = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    var count = 0

    while count < 9999 {
      guard let date = calendar.date(byAdding: .day, value: -(count + 1), to: today) else {
        break
      }

      let dateString = dateFormatter.string(from: date)
      let timeInSeconds = days[dateString] ?? 0

      if timeInSeconds == 0 {
        let todayString = dateFormatter.string(from: today)
        let todayTime = days[todayString] ?? 0
        if todayTime > 0 {
          count += 1
        }
        return count
      }

      count += 1
    }

    return count
  }
}
