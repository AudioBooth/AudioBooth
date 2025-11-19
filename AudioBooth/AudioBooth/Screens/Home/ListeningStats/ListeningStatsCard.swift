import Charts
import Combine
import SwiftUI

struct ListeningStatsCard: View {
  @StateObject var model: Model
  @State private var selectedDay: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Listening Stats")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.primary)

      HStack {
        VStack(alignment: .leading, spacing: 16) {
          todaySection
          weekSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.gray.opacity(0.3), lineWidth: 1)
        )
      }
    }
    .onAppear(perform: model.onAppear)
  }

  var todaySection: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Today")
          .font(.subheadline)
          .foregroundColor(.secondary)

        if model.isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Text(model.todayTime)
            .font(.title2)
            .fontWeight(.semibold)
        }
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Text("This Week")
          .font(.subheadline)
          .foregroundColor(.secondary)

        if model.isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Text(model.totalTime)
            .font(.title3)
            .fontWeight(.medium)
        }
      }
    }
  }

  var weekSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Last 7 Days")
          .font(.caption)
          .foregroundColor(.secondary)

        Spacer()

        if let selectedDay,
          let dayData = model.weekData.first(where: { $0.label == selectedDay })
        {
          Text(formatTime(dayData.timeInSeconds))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.primary)
        }
      }

      if model.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .frame(height: 80)
      } else {
        Chart(model.weekData) { dayData in
          BarMark(
            x: .value("Day", dayData.label),
            y: .value("Time", dayData.timeInSeconds == 0 ? 1 : dayData.timeInSeconds)
          )
          .foregroundStyle(.primary)
          .cornerRadius(2)
        }
        .chartXSelection(value: $selectedDay)
        .chartYAxis(.hidden)
        .chartXAxis {
          AxisMarks(values: model.weekData.map { $0.label }) { value in
            AxisValueLabel()
              .font(.caption2)
              .foregroundStyle(.primary)
          }
        }
        .frame(height: 80)
      }
    }
  }

  private func formatTime(_ seconds: Double) -> String {
    let allowed: Set<Duration.UnitsFormatStyle.Unit>

    if seconds == 0 {
      return "0m"
    } else if seconds > 60 * 60 * 24 {
      allowed = [.days, .hours]
    } else {
      allowed = [.hours, .minutes]
    }

    return Duration.seconds(seconds).formatted(
      .units(allowed: allowed, width: .narrow)
    )
  }
}

extension ListeningStatsCard {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var todayTime: String
    var totalTime: String
    var weekData: [DayData]

    struct DayData: Identifiable {
      let id: String
      let label: String
      let timeInSeconds: Double
      let normalizedValue: Double
    }

    func onAppear() {}

    init(
      isLoading: Bool = false,
      todayTime: String = "0m",
      totalTime: String = "0h",
      weekData: [DayData] = []
    ) {
      self.isLoading = isLoading
      self.todayTime = todayTime
      self.totalTime = totalTime
      self.weekData = weekData
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
      todayTime: "2h 15m",
      totalTime: "178h",
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
