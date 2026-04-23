import Models
import SwiftUI
import WidgetKit

struct ListeningActivityWidget: Widget {
  let kind: String = "ListeningActivityWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ReadingStatsWidgetProvider()) { entry in
      ListeningActivityWidgetView(entry: entry)
    }
    .configurationDisplayName("Listening Activity")
    .description("GitHub-style heatmap of your daily listening")
    .supportedFamilies([.systemMedium])
  }
}

struct ListeningActivityWidgetView: View {
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
    let goalMinutes: Double = stats.dailyGoalMinutes > 0 ? Double(stats.dailyGoalMinutes) : 360

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Listening Activity")
            .font(.subheadline)
            .fontWeight(.semibold)

          Text(formatTime(stats.todayTime) + " today")
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

      ActivityGridView(days: stats.days, goalMinutes: goalMinutes)
    }
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.grid.3x3")
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

private struct ActivityGridView: View {
  let days: [String: Double]
  let goalMinutes: Double

  private let rows = 7
  private let cellSize: CGFloat = 11
  private let spacing: CGFloat = 2
  private let labelFont: Font = .system(size: 7)

  var body: some View {
    GeometryReader { geo in
      let labelWidth: CGFloat = 20
      let gridWidth = geo.size.width - labelWidth - spacing
      let columns = max(Int((gridWidth + spacing) / (cellSize + spacing)), 1)
      let gridData = buildGridData(columns: columns)
      let monthLabels = buildMonthLabels(gridData: gridData, columns: columns)

      HStack(alignment: .top, spacing: spacing) {
        VStack(alignment: .trailing, spacing: spacing) {
          Color.clear.frame(width: labelWidth, height: 10)
          let symbols = weekdaySymbols()
          ForEach(0..<rows, id: \.self) { row in
            if row == 1 || row == 3 || row == 5 {
              Text(symbols[row]).font(labelFont).foregroundStyle(.secondary)
                .frame(width: labelWidth, height: cellSize, alignment: .trailing)
            } else {
              Color.clear.frame(width: labelWidth, height: cellSize)
            }
          }
        }

        HStack(alignment: .top, spacing: spacing) {
          ForEach(0..<columns, id: \.self) { col in
            VStack(alignment: .leading, spacing: spacing) {
              Color.clear
                .frame(width: cellSize, height: 10)
                .overlay(alignment: .bottomLeading) {
                  if let label = monthLabels[col] {
                    Text(label).font(labelFont).foregroundStyle(.secondary)
                      .fixedSize()
                  }
                }

              ForEach(0..<rows, id: \.self) { row in
                let index = col * rows + row
                let cell = gridData[index]
                RoundedRectangle(cornerRadius: 2)
                  .fill(cell.isEmpty ? .clear : colorForMinutes(cell.minutes))
                  .frame(width: cellSize, height: cellSize)
              }
            }
          }
        }
      }
    }
    .frame(height: 10 + spacing + CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing)
  }

  private struct CellData {
    let dateString: String
    let minutes: Double
    let isEmpty: Bool
  }

  private func rowForWeekday(_ weekday: Int) -> Int {
    let calendar = Calendar.current
    return (weekday - calendar.firstWeekday + 7) % 7
  }

  private func weekdaySymbols() -> [String] {
    let calendar = Calendar.current
    let symbols = calendar.shortWeekdaySymbols
    let start = calendar.firstWeekday - 1
    return Array(symbols[start...]) + Array(symbols[..<start])
  }

  private func buildGridData(columns: Int) -> [CellData] {
    let calendar = Calendar.current
    let today = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let todayRow = rowForWeekday(calendar.component(.weekday, from: today))
    let totalDays = (columns - 1) * 7 + todayRow + 1
    let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today)!

    let totalCells = columns * rows
    var cells = [CellData](repeating: CellData(dateString: "", minutes: 0, isEmpty: true), count: totalCells)

    for dayOffset in 0..<totalDays {
      let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate)!
      let weekday = calendar.component(.weekday, from: date)
      let row = rowForWeekday(weekday)
      let col = dayOffset / 7

      guard col < columns, row < rows else { continue }

      let dateString = dateFormatter.string(from: date)
      let minutes = (days[dateString] ?? 0) / 60
      cells[col * rows + row] = CellData(dateString: dateString, minutes: minutes, isEmpty: false)
    }

    return cells
  }

  private func buildMonthLabels(gridData: [CellData], columns: Int) -> [Int: String] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let monthFormatter = DateFormatter()
    monthFormatter.dateFormat = "MMM"

    var labels: [Int: String] = [:]
    var lastMonth = -1

    for col in 0..<columns {
      let cell = gridData[col * rows]
      guard !cell.isEmpty, let date = dateFormatter.date(from: cell.dateString) else { continue }

      let month = Calendar.current.component(.month, from: date)
      if month != lastMonth {
        labels[col] = monthFormatter.string(from: date)
        lastMonth = month
      }
    }

    return labels
  }

  private func colorForMinutes(_ minutes: Double) -> Color {
    guard minutes > 0 else {
      return Color.secondary.opacity(0.15)
    }

    let ratio = minutes / goalMinutes
    switch ratio {
    case 0..<0.25: return Color.widgetAccent.opacity(0.3)
    case 0.25..<0.5: return Color.widgetAccent.opacity(0.5)
    case 0.5..<0.75: return Color.widgetAccent.opacity(0.75)
    default: return Color.widgetAccent
    }
  }
}

#Preview("Listening Activity", as: .systemMedium) {
  ListeningActivityWidget()
} timeline: {
  ReadingStatsWidgetEntry(
    date: Date(),
    stats: WidgetStatsData(
      todayTime: 1800,
      dailyGoalMinutes: 30,
      weekData: [],
      days: generateSampleDays(),
      daysInARow: 5
    )
  )
}

private func generateSampleDays() -> [String: Double] {
  let calendar = Calendar.current
  let today = Date()
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy-MM-dd"

  var days: [String: Double] = [:]
  for i in 0..<120 {
    guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
    let dateString = dateFormatter.string(from: date)
    let random = Double.random(in: 0...1)
    if random > 0.3 {
      days[dateString] = Double.random(in: 300...7200)
    }
  }
  return days
}
