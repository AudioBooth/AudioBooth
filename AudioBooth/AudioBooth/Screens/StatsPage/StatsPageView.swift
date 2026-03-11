import Charts
import Combine
import SwiftUI

struct StatsPageView: View {
  @StateObject var model: Model
  @State private var showGoalPicker = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if model.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
        } else {
          dailyGoalSection

          yearInReviewSection

          statsCardsSection
          recentSessionsSection
        }
      }
      .padding()
    }
    .navigationTitle("Your Stats")
    .navigationBarTitleDisplayMode(.large)
    .onAppear(perform: model.onAppear)
    .sheet(isPresented: $showGoalPicker) {
      goalPickerSheet
        .dynamicTypeSize(.large)
        .presentationDetents([.height(216)])
        .presentationDragIndicator(.hidden)
    }
  }

  private var dailyGoalSection: some View {
    let todayMinutes = model.todayTime / 60
    let goalMinutes = Double(model.dailyGoalMinutes)
    let progress = goalMinutes > 0 ? min(todayMinutes / goalMinutes, 1.0) : 0.0
    let remaining = max(Int(goalMinutes - todayMinutes), 0)

    return VStack(spacing: 20) {
      GeometryReader { proxy in
        let r = proxy.size.width / 2
        ZStack {
          Circle()
            .trim(from: 0.5, to: 1.0)
            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            .frame(width: r * 2, height: r * 2)
            .position(x: r, y: r)

          Circle()
            .trim(from: 0.5, to: 0.5 + 0.5 * CGFloat(progress))
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            .frame(width: r * 2, height: r * 2)
            .position(x: r, y: r)
            .animation(.easeInOut, value: progress)

          VStack(spacing: 6) {
            Text(model.todayTime / 60, format: .number.precision(.fractionLength(0)))
              .font(.system(size: 52, weight: .bold, design: .rounded))

            Text("of my \(model.dailyGoalMinutes)-minute goal")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .position(x: r, y: r * 0.6)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .aspectRatio(2.0, contentMode: .fit)
      .padding(.horizontal)

      Divider()

      VStack(spacing: 6) {
        Text("Today's Listening")
          .font(.headline)

        if remaining > 0 {
          Text("^[\(remaining) minute](inflect: true) to go")
            .foregroundStyle(.primary)
        } else {
          Text("Goal reached!")
            .foregroundStyle(Color.accentColor)
        }

        Button("Adjust Goal") {
          showGoalPicker = true
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .padding(.top, 4)
      }
    }
    .padding()
    .background(.secondary.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private var goalPickerSheet: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button {
          showGoalPicker = false
        } label: {
          Image(systemName: "xmark")
            .tint(.primary)
            .font(.title2)
        }
      }
      .overlay {
        Text("Daily Listening Goal")
          .fontWeight(.semibold)
      }
      .padding(.horizontal)
      .padding(.vertical, 12)

      Divider()

      ZStack {
        Picker(
          "",
          selection: Binding(
            get: { model.dailyGoalMinutes },
            set: { model.onGoalChanged($0) }
          )
        ) {
          ForEach(0...1440, id: \.self) { minutes in
            Text("\(minutes)").tag(minutes)
          }
        }
        .pickerStyle(.wheel)

        Text("1440")
          .monospacedDigit()
          .hidden()
          .overlay(alignment: .leading) {
            HStack(spacing: 12) {
              Text("1440")
                .monospacedDigit()
                .hidden()

              Text("min/day")
                .bold()
                .font(.callout)
            }
            .fixedSize(horizontal: true, vertical: true)
          }
          .allowsHitTesting(false)
      }
    }
  }

  private var yearInReviewSection: some View {
    YearInReviewCard(
      model: YearInReviewCardModel(listeningDays: model.listeningDays)
    )
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

              Text(verbatim: "•")
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
    var todayTime: Double
    var itemsFinished: Int
    var daysListened: Int
    var recentSessions: [SessionData]
    var listeningDays: [String: Double]
    var dailyGoalMinutes: Int

    struct SessionData: Identifiable {
      let id: String
      let title: String
      let timeListening: Double
      let updatedAt: Double
    }

    func onAppear() {}
    func onGoalChanged(_ minutes: Int) {}

    init(
      isLoading: Bool = false,
      totalTime: Double = 0,
      todayTime: Double = 0,
      itemsFinished: Int = 0,
      daysListened: Int = 0,
      recentSessions: [SessionData] = [],
      listeningDays: [String: Double] = [:],
      dailyGoalMinutes: Int = 0
    ) {
      self.isLoading = isLoading
      self.totalTime = totalTime
      self.todayTime = todayTime
      self.itemsFinished = itemsFinished
      self.daysListened = daysListened
      self.recentSessions = recentSessions
      self.listeningDays = listeningDays
      self.dailyGoalMinutes = dailyGoalMinutes
    }
  }
}

extension StatsPageView.Model {
  static var mock: StatsPageView.Model {
    StatsPageView.Model(
      totalTime: 56454.885962963104,
      todayTime: 306,
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
      ],
      listeningDays: [
        "2023-12-01": 120.0,
        "2024-03-15": 200.0,
        "2025-01-05": 180.0,
      ],
      dailyGoalMinutes: 8
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
