import SwiftUI

struct HeatmapColumnsKey: PreferenceKey {
  static var defaultValue: Int = 0
  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

struct ActivityHeatmapView: View {
  let days: [String: Double]
  let goalMinutes: Double

  private let rows = 7
  private let cellSize: CGFloat = 12
  private let spacing: CGFloat = 3
  private let labelFont: Font = .system(size: 9, weight: .semibold)
  private let labelWidth: CGFloat = 20

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GeometryReader { geo in
        let gridWidth = geo.size.width - labelWidth - spacing
        let columns = max(Int((gridWidth + spacing) / (cellSize + spacing)), 1)
        let gridData = buildGridData(columns: columns)
        let monthLabels = buildMonthLabels(gridData: gridData, columns: columns)

        HStack(alignment: .top, spacing: spacing) {
          VStack(alignment: .trailing, spacing: spacing) {
            Color.clear
              .frame(width: labelWidth, height: 12)
              .preference(key: HeatmapColumnsKey.self, value: columns)
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
                  .frame(width: cellSize, height: 12)
                  .overlay(alignment: .bottomLeading) {
                    if let label = monthLabels[col] {
                      Text(label).font(labelFont).foregroundStyle(.secondary)
                        .fixedSize()
                    }
                  }

                ForEach(0..<rows, id: \.self) { row in
                  let index = col * rows + row
                  let cell = gridData[index]
                  RoundedRectangle(cornerRadius: 2.5)
                    .fill(cell.isEmpty ? Color.clear : color(forMinutes: cell.minutes))
                    .frame(width: cellSize, height: cellSize)
                }
              }
            }
          }
        }
      }
      .frame(height: 12 + spacing + CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing)

      HStack(spacing: 6) {
        Text("Less")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)

        HStack(spacing: 3) {
          ForEach(0..<5, id: \.self) { level in
            RoundedRectangle(cornerRadius: 2.5)
              .fill(legendColor(level: level))
              .frame(width: cellSize, height: cellSize)
          }
        }

        Text("More")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
      }
      .padding(.leading, labelWidth + spacing)
    }
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
    let symbols = calendar.veryShortWeekdaySymbols
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
    guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else {
      return Array(repeating: CellData(dateString: "", minutes: 0, isEmpty: true), count: columns * rows)
    }

    let totalCells = columns * rows
    var cells = [CellData](repeating: CellData(dateString: "", minutes: 0, isEmpty: true), count: totalCells)

    for dayOffset in 0..<totalDays {
      guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
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
    var lastLabelColumn: Int?

    for col in 0..<columns {
      let cell = gridData[col * rows]
      guard !cell.isEmpty, let date = dateFormatter.date(from: cell.dateString) else { continue }

      let month = Calendar.current.component(.month, from: date)
      if month != lastMonth {
        if let lastLabelColumn, col - lastLabelColumn < 2 {
          labels[lastLabelColumn] = nil
        }
        labels[col] = monthFormatter.string(from: date)
        lastMonth = month
        lastLabelColumn = col
      }
    }

    return labels
  }

  private func color(forMinutes minutes: Double) -> Color {
    guard minutes > 0 else { return Color.secondary.opacity(0.15) }
    let ratio = goalMinutes > 0 ? minutes / goalMinutes : 0
    switch ratio {
    case ..<0.25: return Color.accentColor.opacity(0.3)
    case ..<0.5: return Color.accentColor.opacity(0.5)
    case ..<0.75: return Color.accentColor.opacity(0.75)
    default: return Color.accentColor
    }
  }

  private func legendColor(level: Int) -> Color {
    switch level {
    case 0: return Color.secondary.opacity(0.15)
    case 1: return Color.accentColor.opacity(0.3)
    case 2: return Color.accentColor.opacity(0.5)
    case 3: return Color.accentColor.opacity(0.75)
    default: return Color.accentColor
    }
  }
}
