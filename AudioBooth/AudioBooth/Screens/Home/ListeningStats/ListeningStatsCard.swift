import Charts
import Combine
import SwiftUI

struct ListeningStatsCard: View {
  @Environment(\.appTheme) var theme
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  @StateObject var model: Model
  @State private var selectedDay: String?

  var body: some View {
    NavigationLink(value: NavigationDestination.stats) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Your Stats")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)

          Spacer()

          Image(systemName: "chevron.right")
            .font(.body)
            .foregroundColor(.secondary)
        }

        HStack(spacing: 0) {
          if isShowingProgress {
            ProgressView()
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          } else if horizontalSizeClass == .regular {
            recentSection
              .padding(.horizontal, 16)

            Divider()
              .overlay(.secondary)

            weekSection
              .padding(.horizontal, 12)

            Divider()
              .overlay(.secondary)

            totalsSection
              .padding(.horizontal, 16)
          } else {
            VStack(alignment: .leading, spacing: 12) {
              todaySection

              Divider()
                .overlay(.secondary)

              weekSection
                .padding(.horizontal, 12)
            }
          }
        }
        .frame(minHeight: 180)
        .padding(.vertical, 12)
        .background(theme.colors.background.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.secondary.opacity(0.3), lineWidth: 2)
        )
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .onAppear(perform: model.onAppear)
  }

  private var isShowingProgress: Bool {
    model.isLoading && model.weekData.isEmpty
  }

  var recentSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      statRow(
        icon: "clock.fill",
        iconColor: .accentColor,
        value: formatTime(model.todayTime),
        label: "today"
      )

      statRow(
        icon: "chart.bar.fill",
        iconColor: .accentColor,
        value: formatTime(model.totalTime),
        label: "this week"
      )

      statRow(
        icon: "flame.fill",
        iconColor: .orange,
        value: "\(model.daysInARow)",
        label: "day streak"
      )
    }
  }

  var totalsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      statRow(
        icon: "calendar",
        iconColor: Color(red: 0.24, green: 0.47, blue: 0.78),
        value: "\(model.daysListened)",
        label: "Days Listened"
      )

      statRow(
        icon: "books.vertical.fill",
        iconColor: Color(red: 0.48, green: 0.36, blue: 0.72),
        value: "\(model.itemsFinished)",
        label: "Items Finished"
      )

      statRow(
        icon: "gauge.with.needle",
        iconColor: .accentColor,
        value: formatTime(model.dailyAverage),
        label: "Daily Avg"
      )
    }
  }

  private func statRow(icon: String, iconColor: Color, value: String, label: LocalizedStringResource) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.footnote)
        .foregroundStyle(iconColor)
        .frame(width: 28, height: 28)
        .background(iconColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: value)
          .font(.callout)
          .fontWeight(.semibold)

        Text(label)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  var todaySection: some View {
    HStack(spacing: 0) {
      Spacer()

      VStack(spacing: 3) {
        Text(formatTime(model.todayTime))
          .font(.callout)
          .fontWeight(.semibold)

        Text("today")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Spacer()

      VStack(spacing: 3) {
        Text(formatTime(model.totalTime))
          .font(.callout)
          .fontWeight(.semibold)

        Text("this week")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Spacer()

      VStack(spacing: 3) {
        HStack {
          Text("\(model.daysInARow)")
            .font(.callout)
            .fontWeight(.bold)
            .foregroundColor(.orange)

          Image(systemName: "flame.fill")
            .font(.callout)
            .foregroundColor(.orange)
            .frame(height: 16)
        }

        Text("day streak")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Spacer()
    }
    .padding(.horizontal, 12)
  }

  var weekSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Minutes Listening (last 7 days)")
        .font(.footnote)
        .fontWeight(.medium)
        .zIndex(0)

      let maxMinutes = model.weekData.map { $0.timeInSeconds / 60 }.max() ?? 0
      let yAxisMax = maxMinutes * 1.3
      let yAxisStep: Double =
        switch yAxisMax {
        case 960...: 240
        case 480...: 120
        case 60...: 60
        case 30...: 15
        default: 5
        }

      Chart(model.weekData) { dayData in
        AreaMark(
          x: .value("Day", dayData.label),
          y: .value("Time", dayData.timeInSeconds / 60)
        )
        .foregroundStyle(
          .linearGradient(
            colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
          )
        )

        LineMark(
          x: .value("Day", dayData.label),
          y: .value("Time", dayData.timeInSeconds / 60)
        )
        .foregroundStyle(Color.accentColor)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .symbol {
          symbol(dayData, isSelected: dayData.label == selectedDay)
        }
      }
      .chartYScale(domain: 0...yAxisMax)
      .chartYAxis {
        AxisMarks(
          position: .leading,
          values: Array(stride(from: 0.0, through: yAxisMax, by: yAxisStep))
        )
      }
      .chartXSelection(value: $selectedDay)
      .chartXAxis {
        AxisMarks(values: model.weekData.map(\.label)) { value in
          AxisValueLabel()
            .font(.caption2)
        }
      }
    }
  }

  private func symbol(_ dayData: ListeningStatsCard.Model.DayData, isSelected: Bool) -> some View {
    Circle()
      .fill(Color.accentColor)
      .frame(width: 8, height: 8)
      .overlay(
        Circle()
          .stroke(isSelected ? .white : .white.opacity(0.3), lineWidth: 2)
      )
      .overlay {
        if isSelected {
          Text(formatTime(dayData.timeInSeconds))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(Color.accentColor)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(theme.colors.background.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: 0, y: -16)
        }
      }

  }

  private func formatTime(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(
      .units(allowed: [.hours, .minutes], width: .narrow)
    )
  }
}

extension ListeningStatsCard {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var todayTime: Double
    var totalTime: Double
    var weekData: [DayData]
    var daysInARow: Int
    var daysListened: Int
    var itemsFinished: Int
    var dailyAverage: Double

    struct DayData: Identifiable {
      let id: String
      let label: String
      let timeInSeconds: Double
    }

    func onAppear() {}

    init(
      isLoading: Bool = false,
      todayTime: Double = 0,
      totalTime: Double = 0,
      weekData: [DayData] = [],
      daysInARow: Int = 0,
      daysListened: Int = 0,
      itemsFinished: Int = 0,
      dailyAverage: Double = 0
    ) {
      self.isLoading = isLoading
      self.todayTime = todayTime
      self.totalTime = totalTime
      self.weekData = weekData
      self.daysInARow = daysInARow
      self.daysListened = daysListened
      self.itemsFinished = itemsFinished
      self.dailyAverage = dailyAverage
    }
  }
}

extension ListeningStatsCard.Model {
  static var mock: ListeningStatsCard.Model {
    let days = [
      DayData(id: "2025-10-11", label: "Sat", timeInSeconds: 1800),
      DayData(id: "2025-10-12", label: "Sun", timeInSeconds: 0),
      DayData(id: "2025-10-13", label: "Mon", timeInSeconds: 3600),
      DayData(id: "2025-10-14", label: "Tue", timeInSeconds: 7200),
      DayData(id: "2025-10-15", label: "Wed", timeInSeconds: 10800),
      DayData(id: "2025-10-16", label: "Thu", timeInSeconds: 5400),
      DayData(id: "2025-10-17", label: "Fri", timeInSeconds: 12000),
    ]

    return ListeningStatsCard.Model(
      todayTime: 135,
      totalTime: 4321,
      weekData: days,
      daysListened: 171,
      itemsFinished: 24,
      dailyAverage: 900
    )
  }
}

#Preview("ListeningStatsCard - Loading") {
  ListeningStatsCard(model: .init(isLoading: true))
    .padding()
}

#Preview("ListeningStatsCard - With Data") {
  ListeningStatsCard(model: .mock)
    .padding()
}

#Preview("ListeningStatsCard - Empty") {
  ListeningStatsCard(model: .init())
    .padding()
}
