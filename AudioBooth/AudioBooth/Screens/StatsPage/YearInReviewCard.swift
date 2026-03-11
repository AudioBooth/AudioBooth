import Combine
import SwiftUI

struct YearInReviewCard: View {
  @StateObject var model: Model
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button(action: {
        withAnimation { isExpanded.toggle() }
        if isExpanded {
          model.onExpanded()
        }
      }) {
        HStack {
          Image(systemName: "headphones")
            .font(.body)
            .foregroundColor(.accentColor)

          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
              Menu {
                ForEach(model.availableYears, id: \.self) { year in
                  Button {
                    model.onYearChanged(year)
                  } label: {
                    Text("\(year, format: .number.grouping(.never))")
                  }
                }
              } label: {
                Text("\(model.year, format: .number.grouping(.never))")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(.accentColor)
              }
              .allowsHitTesting(model.availableYears.count > 1)

              Text("Year in Review")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            }

            Text("Tap to see your stats")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.body)
            .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        VStack(spacing: 16) {
          statsGrid(stats: model.stats)

          Divider()

          topStats(stats: model.stats)
        }
        .redacted(reason: model.isLoading ? .placeholder : [])
      }
    }
    .padding()
    .background(
      LinearGradient(
        colors: [.accentColor.opacity(0.05), .accentColor.opacity(0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(height: 600)
      .allowsHitTesting(false)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func statsGrid(stats: YearInReviewStats) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        statCard(
          value: "\(stats.booksFinished)",
          label: "books finished"
        )

        statCard(
          value: formatTime(stats.timeSpent),
          label: "spent listening"
        )
      }
      .frame(height: 80)

      HStack(spacing: 12) {
        statCard(
          value: "\(stats.sessions)",
          label: "sessions"
        )

        statCard(
          value: "\(stats.booksListened)",
          label: "books listened to"
        )
      }
      .frame(height: 80)
    }
  }

  private func topStats(stats: YearInReviewStats) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        topStatItem(title: "TOP NARRATOR", name: stats.topNarrator.name, time: stats.topNarrator.time)
        topStatItem(title: "TOP GENRE", name: stats.topGenre.name, time: stats.topGenre.time)
      }
      .frame(height: 80)

      HStack(spacing: 12) {
        topStatItem(title: "TOP AUTHOR", name: stats.topAuthor.name, time: stats.topAuthor.time)
        topStatItem(title: "TOP MONTH", name: stats.topMonth.name, time: stats.topMonth.time)
      }
      .frame(height: 80)
    }
  }

  private func statCard(value: String, label: String) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .center, spacing: 2) {
        Text(value)
          .font(.title)
          .fontWeight(.bold)
          .minimumScaleFactor(0.5)

        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .lineLimit(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .background(.background.opacity(0.8))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func topStatItem(title: String, name: String, time: Double) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)

      Text(name)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(1)

      Text(formatTime(time))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.background.opacity(0.8))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func formatTime(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated)
    )
  }
}

extension YearInReviewCard {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var year: Int
    var stats: YearInReviewStats
    var availableYears: [Int]

    func onExpanded() {}
    func onYearChanged(_ year: Int) {}

    init(
      isLoading: Bool = false,
      year: Int,
      stats: YearInReviewStats = .placeholder,
      availableYears: [Int] = []
    ) {
      self.isLoading = isLoading
      self.year = year
      self.stats = stats
      self.availableYears = availableYears
    }
  }
}

struct YearInReviewStats {
  let booksFinished: Int
  let timeSpent: Double
  let sessions: Int
  let booksListened: Int
  let topNarrator: TopStat
  let topGenre: TopStat
  let topAuthor: TopStat
  let topMonth: TopStat

  struct TopStat {
    let name: String
    let time: Double
  }

  static let placeholder = YearInReviewStats(
    booksFinished: 15,
    timeSpent: 55219,
    sessions: 355,
    booksListened: 26,
    topNarrator: .init(name: "Loading Narrator", time: 37113),
    topGenre: .init(name: "Loading Genre", time: 54446),
    topAuthor: .init(name: "Loading Author", time: 37113),
    topMonth: .init(name: "Loading Month", time: 33027)
  )
}

#Preview("YearInReviewCard - Loading") {
  YearInReviewCard(
    model: .init(
      isLoading: true,
      year: 2025,
      availableYears: [2023, 2024, 2025]
    )
  )
  .padding()
}

#Preview("YearInReviewCard - With Data") {
  YearInReviewCard(
    model: .init(
      year: 2025,
      stats: YearInReviewStats(
        booksFinished: 15,
        timeSpent: 55219,
        sessions: 355,
        booksListened: 26,
        topNarrator: .init(name: "Andrea Parsneau", time: 37113),
        topGenre: .init(name: "Science Fiction & Fantasy", time: 54446),
        topAuthor: .init(name: "Rhaegar", time: 37113),
        topMonth: .init(name: "November", time: 33027)
      ),
      availableYears: [2023, 2024, 2025]
    )
  )
  .padding()
}
