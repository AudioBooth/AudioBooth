import API
import Combine
import Foundation
import UIKit

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
    todayTime = formatTime(stats.today)
    weekData = calculateWeekData(stats.days)

    let weekTotal = weekData.reduce(0) { $0 + $1.timeInSeconds }
    totalTime = formatTime(weekTotal)

    isLoading = false
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

  private func formatTime(_ seconds: Double) -> String {
    let allowed: Set<Duration.UnitsFormatStyle.Unit>

    if seconds > 60 * 60 * 24 {
      allowed = [.days, .hours]
    } else {
      allowed = [.hours, .minutes]
    }

    return Duration.seconds(seconds).formatted(
      .units(allowed: allowed, width: .narrow)
    )
  }
}
