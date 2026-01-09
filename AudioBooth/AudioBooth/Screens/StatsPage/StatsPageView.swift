import Charts
import Combine
import SwiftUI

struct StatsPageView: View {
  @StateObject var model: Model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if model.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
        } else {
          statsCardsSection
          recentSessionsSection
        }
      }
      .padding()
    }
    .navigationTitle("Your Stats")
    .navigationBarTitleDisplayMode(.large)
    .onAppear(perform: model.onAppear)
  }

  private var statsCardsSection: some View {
    HStack(spacing: 12) {
      statCard(
        value: "\(model.itemsFinished)",
        label: "Items Finished"
      )

      statCard(
        value: "\(model.daysListened)",
        label: "Days Listened"
      )

      statCard(
        value: formatMinutes(model.totalTime),
        label: "Minutes Listening"
      )
    }
  }

  private func statCard(value: String, label: String) -> some View {
    VStack(spacing: 8) {
      Text(value)
        .font(.title)
        .fontWeight(.bold)
        .foregroundColor(.accentColor)

      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .background(.secondary.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var recentSessionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recent Sessions")
        .font(.headline)

      ForEach(model.recentSessions) { session in
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
              .font(.subheadline)
              .fontWeight(.medium)
              .lineLimit(2)

            HStack(spacing: 8) {
              Text(formatTime(session.timeListening))
                .font(.caption)
                .foregroundColor(.accentColor)

              Text("•")
                .font(.caption)
                .foregroundColor(.secondary)

              Text(formatDate(session.updatedAt))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  private func formatTime(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated)
    )
  }

  private func formatMinutes(_ seconds: Double) -> String {
    let minutes = Int(ceil(seconds / 60))
    return "\(minutes.formatted())"
  }

  private func formatDate(_ timestamp: Double) -> String {
    let date = Date(timeIntervalSince1970: timestamp / 1000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

extension StatsPageView {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var totalTime: Double
    var itemsFinished: Int
    var daysListened: Int
    var recentSessions: [SessionData]

    struct SessionData: Identifiable {
      let id: String
      let title: String
      let timeListening: Double
      let updatedAt: Double
    }

    func onAppear() {}

    init(
      isLoading: Bool = false,
      totalTime: Double = 0,
      itemsFinished: Int = 0,
      daysListened: Int = 0,
      recentSessions: [SessionData] = []
    ) {
      self.isLoading = isLoading
      self.totalTime = totalTime
      self.itemsFinished = itemsFinished
      self.daysListened = daysListened
      self.recentSessions = recentSessions
    }
  }
}

extension StatsPageView.Model {
  static var mock: StatsPageView.Model {
    StatsPageView.Model(
      totalTime: 56454.885962963104,
      itemsFinished: 5,
      daysListened: 42,
      recentSessions: [
        SessionData(
          id: "1",
          title: "Azarinth Healer: Book One",
          timeListening: 22,
          updatedAt: Date().timeIntervalSince1970 * 1000
        ),
        SessionData(
          id: "2",
          title: "Jake's Magical Market 3",
          timeListening: 1,
          updatedAt: Date().addingTimeInterval(-86400).timeIntervalSince1970 * 1000
        ),
      ]
    )
  }
}

#Preview("StatsPageView - Loading") {
  NavigationStack {
    StatsPageView(model: .init(isLoading: true))
  }
}

#Preview("StatsPageView - With Data") {
  NavigationStack {
    StatsPageView(model: .mock)
  }
}
