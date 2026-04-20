import Foundation

public struct WidgetStatsData: Codable, Sendable {
  public let todayTime: Double
  public let dailyGoalMinutes: Int
  public let weekData: [DayEntry]
  public let days: [String: Double]
  public let daysInARow: Int
  public let updatedAt: Date

  public struct DayEntry: Codable, Sendable {
    public let date: String
    public let label: String
    public let timeInSeconds: Double

    public init(date: String, label: String, timeInSeconds: Double) {
      self.date = date
      self.label = label
      self.timeInSeconds = timeInSeconds
    }
  }

  public init(
    todayTime: Double,
    dailyGoalMinutes: Int,
    weekData: [DayEntry],
    days: [String: Double],
    daysInARow: Int,
    updatedAt: Date = Date()
  ) {
    self.todayTime = todayTime
    self.dailyGoalMinutes = dailyGoalMinutes
    self.weekData = weekData
    self.days = days
    self.daysInARow = daysInARow
    self.updatedAt = updatedAt
  }

  public var goalProgress: Double {
    guard dailyGoalMinutes > 0 else { return 0 }
    return min(todayTime / 60 / Double(dailyGoalMinutes), 1.0)
  }

  public var weekTotal: Double {
    weekData.reduce(0) { $0 + $1.timeInSeconds }
  }
}
