import Combine
import Models
import SwiftUI

struct ProgressCard: View {
  let model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.isFinished {
        finishedRow
      } else {
        progressRow
      }
      startedRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.fill.tertiary)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var progressRow: some View {
    HStack(spacing: 4) {
      Image(systemName: "chart.line.uptrend.xyaxis")
        .foregroundStyle(.secondary)

      Text(model.progress.formatted(.percent.precision(.fractionLength(0))))
        .fontWeight(.medium)

      if model.timeRemaining.isFinite, model.timeRemaining > 0 {
        Text("·")
          .foregroundStyle(.secondary)

        Text(
          Duration.seconds(model.timeRemaining).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated)
          ) + " remaining"
        )
        .foregroundStyle(.secondary)
      }
    }
    .font(.subheadline)
  }

  private var finishedRow: some View {
    HStack(spacing: 4) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)

      Text("Finished")
        .fontWeight(.medium)

      if let finishedAt = model.finishedAt {
        Text("·")
          .foregroundStyle(.secondary)

        Text(finishedAt.formatted(date: .abbreviated, time: .omitted))
          .foregroundStyle(.secondary)
      }
    }
    .font(.subheadline)
  }

  private var startedRow: some View {
    HStack(spacing: 4) {
      Image(systemName: "calendar")
        .foregroundStyle(.secondary)

      Text("Started")
        .foregroundStyle(.secondary)

      Text(model.startedAt.formatted(date: .abbreviated, time: .omitted))
        .foregroundStyle(.secondary)
    }
    .font(.subheadline)
  }
}

extension ProgressCard {
  @Observable
  class Model: ObservableObject {
    var progress: Double
    var timeRemaining: TimeInterval
    var startedAt: Date
    var finishedAt: Date?
    var isFinished: Bool

    init(
      progress: Double = 0,
      timeRemaining: TimeInterval,
      startedAt: Date = Date(),
      finishedAt: Date? = nil,
      isFinished: Bool = false
    ) {
      self.progress = progress
      self.timeRemaining = timeRemaining
      self.startedAt = startedAt
      self.finishedAt = finishedAt
      self.isFinished = isFinished
    }
  }
}

extension ProgressCard.Model {
  convenience init(_ mediaProgress: MediaProgress) {
    self.init(
      progress: mediaProgress.progress > 0 ? mediaProgress.progress : mediaProgress.ebookProgress ?? 0,
      timeRemaining: mediaProgress.remaining,
      startedAt: mediaProgress.startedAt,
      finishedAt: mediaProgress.finishedAt,
      isFinished: mediaProgress.isFinished
    )
  }
}

#Preview("In Progress") {
  ProgressCard(
    model: .init(
      progress: 0.45,
      timeRemaining: 9000,
      startedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date())!
    )
  )
  .padding()
}

#Preview("Finished") {
  ProgressCard(
    model: .init(
      progress: 1.0,
      timeRemaining: 0,
      startedAt: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
      finishedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
      isFinished: true
    )
  )
  .padding()
}
