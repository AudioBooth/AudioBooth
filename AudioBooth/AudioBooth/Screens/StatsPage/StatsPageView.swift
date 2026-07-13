import Charts
import Combine
import SwiftUI

struct StatsPageView: View {
  @Environment(\.appTheme) var theme
  @StateObject var model: Model
  @State private var showGoalPicker = false
  @State private var mostListenedTab: MostListenedTab = .genres
  @State private var heatmapWeeks: Int = 0

  enum MostListenedTab: String, CaseIterable, Identifiable {
    case genres = "Genres"
    case authors = "Authors"
    case narrators = "Narrators"

    var id: String { rawValue }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if model.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
        } else {
          dailyGoalSection
          heroSection
          periodSummarySection
          streakSection
          statsCardsSection
          activitySection
          mostListenedSection
          YearInReviewCard(model: YearInReviewCardModel(listeningDays: model.listeningDays))
          recentSessionsSection
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 16)
    }
    .background(theme.colors.background.page)
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

}

extension StatsPageView {
  private var dailyGoalSection: some View {
    DailyGoalCard(
      todayTime: model.todayTime,
      goalMinutes: model.dailyGoalMinutes,
      onEdit: { showGoalPicker = true }
    )
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
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .pickerStyle(.wheel)
        #else
        .pickerStyle(.menu)
        #endif

        Text(verbatim: "1440")
          .monospacedDigit()
          .hidden()
          .overlay(alignment: .leading) {
            HStack(spacing: 12) {
              Text(verbatim: "1440")
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

}

extension StatsPageView {
  private var heroSection: some View {
    let hours = Int((model.totalTime / 3600).rounded())
    let days = Int((model.totalTime / 86400).rounded())

    return VStack(spacing: 10) {
      Text("ALL-TIME LISTENING")
        .font(.caption)
        .fontWeight(.semibold)
        .tracking(1)
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(hours.formatted())
          .font(.system(size: 64, weight: .bold, design: .rounded))
          .foregroundStyle(Color.accentColor)
          .monospacedDigit()

        Text("hrs")
          .font(.title2.weight(.semibold))
          .foregroundStyle(Color.accentColor)
      }

      Text("≈ ^[\(days) day](inflect: true) of nonstop playback")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity)
    .background(theme.colors.background.card)
    .clipShape(RoundedRectangle(cornerRadius: 24))
  }

}

extension StatsPageView {
  private var periodSummarySection: some View {
    let weekSeconds = sumListeningDays(in: .weekOfYear)
    let monthSeconds = sumListeningDays(in: .month)

    return HStack(spacing: 10) {
      periodCard(label: "TODAY", seconds: model.todayTime)
      periodCard(label: "THIS WEEK", seconds: weekSeconds)
      periodCard(label: "THIS MONTH", seconds: monthSeconds)
    }
  }

  private func periodCard(label: String, seconds: Double) -> some View {
    VStack(alignment: .center, spacing: 6) {
      Text(label)
        .font(.caption2)
        .fontWeight(.semibold)
        .tracking(0.5)
        .foregroundStyle(.secondary)

      Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: .narrow))
        .font(.title3.weight(.bold))
        .foregroundStyle(.primary)
        .monospacedDigit()
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .padding(.horizontal, 8)
    .background(theme.colors.background.card)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func sumListeningDays(in component: Calendar.Component) -> Double {
    let calendar = Calendar.current
    let now = Date()
    guard let interval = calendar.dateInterval(of: component, for: now) else { return 0 }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    return model.listeningDays.reduce(0) { total, entry in
      guard let date = formatter.date(from: entry.key),
        interval.contains(date) || calendar.isDate(date, inSameDayAs: now)
      else { return total }
      return total + entry.value
    }
  }

}

extension StatsPageView {
  private var streakSection: some View {
    let (current, longest) = StreakCalculator.compute(from: model.listeningDays)

    return HStack(spacing: 0) {
      streakItem(
        icon: "flame.fill",
        iconColor: .accentColor,
        title: "CURRENT",
        value: current,
        valueColor: .accentColor,
        caption: "day streak"
      )

      Divider()
        .frame(height: 56)

      streakItem(
        icon: "trophy.fill",
        iconColor: .secondary,
        title: "LONGEST",
        value: longest,
        valueColor: .primary,
        caption: "personal best"
      )
    }
    .frame(maxWidth: .infinity)
    .background(theme.colors.background.card)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func streakItem(
    icon: String,
    iconColor: Color,
    title: String,
    value: Int,
    valueColor: Color,
    caption: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(iconColor)
          .frame(width: 24, height: 24)
          .background(iconColor.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8))

        Text(title)
          .font(.caption2)
          .fontWeight(.semibold)
          .tracking(0.5)
          .foregroundStyle(.secondary)
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(value)")
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(valueColor)
          .monospacedDigit()

        Text("days")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      Text(caption)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
  }

}

extension StatsPageView {
  private var statsCardsSection: some View {
    HStack(spacing: 10) {
      statCard(
        icon: "calendar",
        iconColor: Color(red: 0.24, green: 0.47, blue: 0.78),
        value: "\(model.daysListened)",
        label: "Days Listened"
      )

      statCard(
        icon: "books.vertical.fill",
        iconColor: Color(red: 0.48, green: 0.36, blue: 0.72),
        value: "\(model.itemsFinished)",
        label: "Items Finished"
      )

      statCard(
        icon: "gauge.with.needle",
        iconColor: .accentColor,
        value: Duration.seconds(dailyAverageSeconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)),
        label: "Daily Avg"
      )
    }
  }

  private var dailyAverageSeconds: Double {
    guard model.daysListened > 0 else { return 0 }
    return model.totalTime / Double(model.daysListened)
  }

  private var activityGoalMinutes: Double {
    if model.dailyGoalMinutes > 0 { return Double(model.dailyGoalMinutes) }
    let average = dailyAverageSeconds / 60
    return average > 0 ? average : 60
  }

  private func statCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: icon)
        .font(.subheadline)
        .foregroundStyle(iconColor)
        .frame(width: 30, height: 30)
        .background(iconColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)
          .minimumScaleFactor(0.6)
          .lineLimit(1)

        Text(label)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(theme.colors.background.card)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

}

extension StatsPageView {
  private var activitySection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Activity")
          .font(.subheadline.weight(.semibold))

        Spacer()

        if heatmapWeeks > 0 {
          Text("Last \(heatmapWeeks) weeks")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        }
      }

      ActivityHeatmapView(
        days: model.listeningDays,
        goalMinutes: activityGoalMinutes
      )
      .onPreferenceChange(HeatmapColumnsKey.self) { count in
        heatmapWeeks = count
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.background.card)
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }

}

extension StatsPageView {
  private var mostListenedSection: some View {
    let entries: [Model.RankedEntry] = {
      switch mostListenedTab {
      case .genres: return model.topGenres
      case .authors: return model.topAuthors
      case .narrators: return model.topNarrators
      }
    }()

    return VStack(alignment: .leading, spacing: 14) {
      Text("Most Listened")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 4)

      VStack(spacing: 12) {
        Picker("", selection: $mostListenedTab) {
          ForEach(MostListenedTab.allCases) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)

        if entries.isEmpty {
          Text("No data yet")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
          VStack(spacing: 12) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
              rankedRow(index: index + 1, entry: entry, max: entries.first?.seconds ?? 1)
            }
          }
        }
      }
      .padding(16)
      .background(theme.colors.background.card)
      .clipShape(RoundedRectangle(cornerRadius: 20))
    }
  }

  private func rankedRow(index: Int, entry: Model.RankedEntry, max: Double) -> some View {
    HStack(spacing: 12) {
      Text("\(index)")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(index <= 3 ? Color.accentColor : Color.secondary)
        .frame(width: 18, alignment: .center)
        .monospacedDigit()

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          HStack(spacing: 4) {
            Text(entry.name)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)

            if let subtitle = entry.subtitle {
              Text(verbatim: "· \(subtitle)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }

          Spacer(minLength: 8)

          Text(Duration.seconds(entry.seconds), format: .units(allowed: [.hours], width: .narrow))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .fixedSize()
        }

        GeometryReader { geo in
          let ratio = max > 0 ? CGFloat(entry.seconds / max) : 0
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.secondary.opacity(0.15))
            Capsule()
              .fill(Color.accentColor)
              .frame(width: geo.size.width * ratio)
          }
        }
        .frame(height: 5)
      }
    }
  }
}

extension StatsPageView {
  private var recentSessionsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Recent Sessions")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 4)

      LazyVStack(spacing: 0) {
        ForEach(Array(model.recentSessions.enumerated()), id: \.element.id) { index, session in
          sessionRow(session)
            .onAppear {
              if index >= model.recentSessions.count - 3 {
                model.onLoadMoreSessions()
              }
            }

          if index < model.recentSessions.count - 1 {
            Divider()
              .padding(.leading, 16)
          }
        }

        if model.isLoadingMoreSessions {
          ProgressView()
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
      }
      .background(theme.colors.background.card)
      .clipShape(RoundedRectangle(cornerRadius: 20))
    }
  }

  private func sessionRow(_ session: Model.SessionData) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(session.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)

        Text(formatDate(session.updatedAt))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 3) {
        Text(Duration.seconds(session.timeListening), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
          .font(.subheadline.weight(.bold))
          .foregroundStyle(.primary)
          .monospacedDigit()

        Text("LISTENED")
          .font(.system(size: 9, weight: .semibold))
          .tracking(0.5)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

extension StatsPageView {
  private func formatDate(_ timestamp: Double) -> String {
    let date = Date(timeIntervalSince1970: timestamp / 1000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

private enum StreakCalculator {
  static func compute(from days: [String: Double]) -> (current: Int, longest: Int) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let activeDates: Set<Date> = Set(
      days.compactMap { key, value in
        guard value > 0, let date = formatter.date(from: key) else { return nil }
        return Calendar.current.startOfDay(for: date)
      }
    )

    guard !activeDates.isEmpty else { return (0, 0) }

    let calendar = Calendar.current
    let sorted = activeDates.sorted()

    var longest = 1
    var run = 1
    for i in 1..<sorted.count {
      if let prev = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
        calendar.isDate(prev, inSameDayAs: sorted[i])
      {
        run += 1
        longest = max(longest, run)
      } else {
        run = 1
      }
    }

    var current = 0
    var cursor = calendar.startOfDay(for: Date())
    if !activeDates.contains(cursor) {
      cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
    }
    while activeDates.contains(cursor) {
      current += 1
      guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = prev
    }

    return (current, longest)
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
    var topGenres: [RankedEntry]
    var topAuthors: [RankedEntry]
    var topNarrators: [RankedEntry]
    var isLoadingMoreSessions: Bool
    var hasMoreSessions: Bool

    struct SessionData: Identifiable {
      let id: String
      let title: String
      let timeListening: Double
      let updatedAt: Double
    }

    struct RankedEntry: Identifiable {
      let name: String
      let subtitle: String?
      let seconds: Double

      var id: String { name }
    }

    func onAppear() {}
    func onGoalChanged(_ minutes: Int) {}
    func onLoadMoreSessions() {}

    init(
      isLoading: Bool = false,
      totalTime: Double = 0,
      todayTime: Double = 0,
      itemsFinished: Int = 0,
      daysListened: Int = 0,
      recentSessions: [SessionData] = [],
      listeningDays: [String: Double] = [:],
      dailyGoalMinutes: Int = 0,
      topGenres: [RankedEntry] = [],
      topAuthors: [RankedEntry] = [],
      topNarrators: [RankedEntry] = [],
      isLoadingMoreSessions: Bool = false,
      hasMoreSessions: Bool = false
    ) {
      self.isLoading = isLoading
      self.totalTime = totalTime
      self.todayTime = todayTime
      self.itemsFinished = itemsFinished
      self.daysListened = daysListened
      self.recentSessions = recentSessions
      self.listeningDays = listeningDays
      self.dailyGoalMinutes = dailyGoalMinutes
      self.topGenres = topGenres
      self.topAuthors = topAuthors
      self.topNarrators = topNarrators
      self.isLoadingMoreSessions = isLoadingMoreSessions
      self.hasMoreSessions = hasMoreSessions
    }
  }
}

extension StatsPageView.Model {
  static var mock: StatsPageView.Model {
    StatsPageView.Model(
      totalTime: 11_761_988,
      todayTime: 306,
      itemsFinished: 5,
      daysListened: 163,
      recentSessions: [
        SessionData(
          id: "1",
          title: "Azarinth Healer: Book One",
          timeListening: 3720,
          updatedAt: Date().timeIntervalSince1970 * 1000
        ),
        SessionData(
          id: "2",
          title: "Jake's Magical Market 3",
          timeListening: 1200,
          updatedAt: Date().addingTimeInterval(-86400).timeIntervalSince1970 * 1000
        ),
        SessionData(
          id: "3",
          title: "Mark of the Fool 10",
          timeListening: 3480,
          updatedAt: Date().addingTimeInterval(-86400 * 2).timeIntervalSince1970 * 1000
        ),
      ],
      listeningDays: Self.mockListeningDays(),
      dailyGoalMinutes: 60,
      topGenres: [
        .init(name: "Science Fiction & Fantasy", subtitle: nil, seconds: 11_268_000),
        .init(name: "Teen & Young Adult", subtitle: nil, seconds: 240_000),
        .init(name: "LGBTQ+", subtitle: nil, seconds: 168_000),
        .init(name: "Literature & Fiction", subtitle: nil, seconds: 120_000),
        .init(name: "Mystery & Thriller", subtitle: nil, seconds: 72_000),
      ],
      topAuthors: [
        .init(name: "Selkie Myth", subtitle: "16 titles", seconds: 763_200),
        .init(name: "J. M. Clarke", subtitle: "10 titles", seconds: 496_800),
        .init(name: "Kyle Kirrin", subtitle: "6 titles", seconds: 270_000),
        .init(name: "Jakob H. Greif", subtitle: "7 titles", seconds: 230_400),
        .init(name: "R. P. Jones", subtitle: "3 titles", seconds: 133_200),
      ],
      topNarrators: [
        .init(name: "Travis Baldree", subtitle: "19 titles", seconds: 903_600),
        .init(name: "Andrea Emmes", subtitle: "16 titles", seconds: 763_200),
        .init(name: "Daniel Thomas May", subtitle: "7 titles", seconds: 230_400),
        .init(name: "Mandy McCullough", subtitle: "3 titles", seconds: 104_400),
        .init(name: "Stephanie Savannah", subtitle: "3 titles", seconds: 86_400),
      ]
    )
  }

  private static func mockListeningDays() -> [String: Double] {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    var days: [String: Double] = [:]
    for offset in 0..<196 {
      guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
      let key = formatter.string(from: date)
      let seed = (offset * 7919) % 100
      if seed < 70 {
        days[key] = Double(600 + (seed * 90))
      }
    }
    return days
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
