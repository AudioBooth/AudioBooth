import Charts
import Models
import SwiftUI
import WidgetKit

struct WeeklyListeningWidget: Widget {
  let kind: String = "WeeklyListeningWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ReadingStatsWidgetProvider()) { entry in
      WeeklyListeningWidgetView(entry: entry)
    }
    .configurationDisplayName("Weekly Listening")
    .description("See your listening activity for the past week")
    .supportedFamilies([.systemMedium])
  }
}

struct WeeklyListeningWidgetView: View {
  let entry: ReadingStatsWidgetEntry

  var body: some View {
    if let stats = entry.stats {
      contentView(stats)
        .containerBackground(.fill.tertiary, for: .widget)
    } else {
      emptyView
        .containerBackground(.fill.tertiary, for: .widget)
    }
  }

  private func contentView(_ stats: WidgetStatsData) -> some View {
    let maxMinutes = stats.weekData.map { $0.timeInSeconds / 60 }.max() ?? 0
    let yAxisMax = max(maxMinutes * 1.3, 1)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Weekly Listening")
            .font(.subheadline)
            .fontWeight(.semibold)

          Text(formatTime(stats.weekTotal))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if stats.daysInARow > 0 {
          HStack(spacing: 2) {
            Text("\(stats.daysInARow)")
              .font(.caption)
              .fontWeight(.bold)
              .foregroundStyle(.orange)

            Image(systemName: "flame.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }

      Chart(stats.weekData, id: \.date) { day in
        BarMark(
          x: .value("Day", day.label),
          y: .value("Minutes", day.timeInSeconds / 60)
        )
        .foregroundStyle(Color.accentColor.gradient)
        .cornerRadius(4)
      }
      .chartYScale(domain: 0...yAxisMax)
      .chartYAxis {
        AxisMarks(position: .leading) { value in
          AxisValueLabel {
            if let minutes = value.as(Double.self) {
              Text("\(Int(minutes))")
                .font(.system(size: 8))
            }
          }
        }
      }
      .chartXAxis {
        AxisMarks { _ in
          AxisValueLabel()
            .font(.system(size: 9))
        }
      }
    }
    .padding(16)
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.bar")
        .font(.title2)
        .foregroundStyle(.secondary)

      Text("No listening data yet")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func formatTime(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated)
    )
  }
}

#Preview("Weekly Listening", as: .systemMedium) {
  WeeklyListeningWidget()
} timeline: {
  ReadingStatsWidgetEntry(date: Date(), stats: .placeholder)
  ReadingStatsWidgetEntry(date: Date(), stats: nil)
}
