import Models
import SwiftUI
import WidgetKit

struct DailyGoalWidget: Widget {
  let kind: String = "DailyGoalWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ReadingStatsWidgetProvider()) { entry in
      DailyGoalWidgetView(entry: entry)
    }
    .configurationDisplayName("Daily Goal")
    .description("Track your daily listening goal progress")
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

struct DailyGoalWidgetView: View {
  let entry: ReadingStatsWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      circularView
    default:
      smallView
    }
  }

  private var smallView: some View {
    let stats = entry.stats
    let progress = stats?.goalProgress ?? 0
    let todayMinutes = Int((stats?.todayTime ?? 0) / 60)
    let goalMinutes = stats?.dailyGoalMinutes ?? 0
    let streak = stats?.daysInARow ?? 0

    return VStack(spacing: 6) {
      ZStack {
        Circle()
          .stroke(Color.secondary.opacity(0.2), lineWidth: 10)

        Circle()
          .trim(from: 0, to: CGFloat(progress))
          .stroke(
            progress >= 1.0 ? Color.green : Color.accentColor,
            style: StrokeStyle(lineWidth: 10, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut, value: progress)

        VStack(spacing: 2) {
          Text("\(todayMinutes)")
            .font(.system(.title, design: .rounded, weight: .bold))
            .minimumScaleFactor(0.5)

          Text("of \(goalMinutes) min")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 8)

      if streak > 0 {
        HStack(spacing: 2) {
          Text("\(streak)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.orange)

          Image(systemName: "flame.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }
    }
    .padding(12)
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private var circularView: some View {
    let progress = entry.stats?.goalProgress ?? 0
    let todayMinutes = Int((entry.stats?.todayTime ?? 0) / 60)

    return ZStack {
      AccessoryWidgetBackground()

      Gauge(value: progress) {
        Image(systemName: "book.fill")
      } currentValueLabel: {
        Text("\(todayMinutes)")
          .font(.system(.body, design: .rounded, weight: .bold))
      }
      .gaugeStyle(.accessoryCircular)
    }
  }
}

#Preview("Daily Goal - Small", as: .systemSmall) {
  DailyGoalWidget()
} timeline: {
  ReadingStatsWidgetEntry(date: Date(), stats: .placeholder)
  ReadingStatsWidgetEntry(date: Date(), stats: nil)
}

#Preview("Daily Goal - Circular", as: .accessoryCircular) {
  DailyGoalWidget()
} timeline: {
  ReadingStatsWidgetEntry(date: Date(), stats: .placeholder)
}
