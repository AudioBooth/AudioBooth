import Foundation
import Models
import WidgetKit

struct ReadingStatsWidgetEntry: TimelineEntry {
  let date: Date
  let stats: WidgetStatsData?
}

struct ReadingStatsWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> ReadingStatsWidgetEntry {
    ReadingStatsWidgetEntry(date: Date(), stats: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (ReadingStatsWidgetEntry) -> Void) {
    let entry = ReadingStatsWidgetEntry(date: Date(), stats: loadStats() ?? .placeholder)
    completion(entry)
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ReadingStatsWidgetEntry>) -> Void
  ) {
    let entry = ReadingStatsWidgetEntry(date: Date(), stats: loadStats())

    let calendar = Calendar.current
    let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
    let timeline = Timeline(entries: [entry], policy: .after(nextMidnight))
    completion(timeline)
  }

  private func loadStats() -> WidgetStatsData? {
    guard let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS"),
      let data = sharedDefaults.data(forKey: "listeningStats"),
      let stats = try? JSONDecoder().decode(WidgetStatsData.self, from: data)
    else {
      return nil
    }
    return stats
  }
}

extension WidgetStatsData {
  static var placeholder: WidgetStatsData {
    WidgetStatsData(
      todayTime: 1800,
      dailyGoalMinutes: 30,
      weekData: [
        DayEntry(date: "2026-04-13", label: "Sun", timeInSeconds: 1200),
        DayEntry(date: "2026-04-14", label: "Mon", timeInSeconds: 2400),
        DayEntry(date: "2026-04-15", label: "Tue", timeInSeconds: 600),
        DayEntry(date: "2026-04-16", label: "Wed", timeInSeconds: 3600),
        DayEntry(date: "2026-04-17", label: "Thu", timeInSeconds: 1800),
        DayEntry(date: "2026-04-18", label: "Fri", timeInSeconds: 2700),
        DayEntry(date: "2026-04-19", label: "Sat", timeInSeconds: 1800),
      ],
      days: [:],
      daysInARow: 5
    )
  }
}
