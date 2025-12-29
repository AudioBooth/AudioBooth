import Charts
import Combine
import SwiftUI

struct ListeningStatsCard: View {
  @StateObject var model: Model
  @State private var selectedDay: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your Stats")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.primary)

      HStack {
        VStack(alignment: .leading, spacing: 12) {
          if model.isLoading {
            ProgressView()
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          } else {
            todaySection

            Divider()
              .overlay(.secondary)

            weekSection
              .padding(.horizontal, 12)
          }
        }
        .frame(height: 180)
        .padding(.vertical, 12)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.secondary.opacity(0.3), lineWidth: 2)
        )
      }
    }
    .onAppear(perform: model.onAppear)
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
        AxisMarks(position: .leading)
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
            .background(.background)
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

    struct DayData: Identifiable {
      let id: String
      let label: String
      let timeInSeconds: Double
      let normalizedValue: Double
    }

    func onAppear() {}

    init(
      isLoading: Bool = false,
      todayTime: Double = 0,
      totalTime: Double = 0,
      weekData: [DayData] = [],
      daysInARow: Int = 0
    ) {
      self.isLoading = isLoading
      self.todayTime = todayTime
      self.totalTime = totalTime
      self.weekData = weekData
      self.daysInARow = daysInARow
    }
  }
}

extension ListeningStatsCard.Model {
  static var mock: ListeningStatsCard.Model {
    let days = [
      DayData(id: "2025-10-11", label: "Sat", timeInSeconds: 1800, normalizedValue: 0.15),
      DayData(id: "2025-10-12", label: "Sun", timeInSeconds: 0, normalizedValue: 0.0),
      DayData(id: "2025-10-13", label: "Mon", timeInSeconds: 3600, normalizedValue: 0.3),
      DayData(id: "2025-10-14", label: "Tue", timeInSeconds: 7200, normalizedValue: 0.6),
      DayData(id: "2025-10-15", label: "Wed", timeInSeconds: 10800, normalizedValue: 0.9),
      DayData(id: "2025-10-16", label: "Thu", timeInSeconds: 5400, normalizedValue: 0.45),
      DayData(id: "2025-10-17", label: "Fri", timeInSeconds: 12000, normalizedValue: 1.0),
    ]

    return ListeningStatsCard.Model(
      todayTime: 135,
      totalTime: 4321,
      weekData: days
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
