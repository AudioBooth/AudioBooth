import Models
import SwiftUI

struct PlaybackHistoryRow: View {
  let model: Model

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: model.actionType.icon)
        .foregroundStyle(model.actionType.color)
        .frame(width: 24)
        .font(.body)

      Text(model.title ?? model.actionType.displayName)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fontWeight(.medium)

      Text(formatDuration(model.position))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .font(.callout)
  }

  private func formatDuration(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
  }
}

extension PlaybackHistoryRow {
  struct Model: Identifiable {
    let id: String
    let actionType: PlaybackHistory.ActionType
    let title: String?
    let position: TimeInterval
    let timestamp: Date

    init(
      id: String = UUID().uuidString,
      actionType: PlaybackHistory.ActionType,
      title: String? = nil,
      position: TimeInterval,
      timestamp: Date
    ) {
      self.id = id
      self.actionType = actionType
      self.title = title
      self.position = position
      self.timestamp = timestamp
    }

    init(from history: PlaybackHistory) {
      self.id = history.id
      self.actionType = history.action
      self.title = history.title
      self.position = history.position
      self.timestamp = history.timestamp
    }
  }
}

extension PlaybackHistory.ActionType {
  var icon: String {
    switch self {
    case .play: "play.fill"
    case .pause: "pause.fill"
    case .seek: "slider.horizontal.below.rectangle"
    case .sync: "arrow.triangle.2.circlepath"
    case .chapter: "list.dash"
    case .timerStarted: "timer"
    case .timerCompleted: "timer.circle.fill"
    case .timerExtended: "timer.circle"
    }
  }

  var displayName: String {
    switch self {
    case .play: String(localized: "Play")
    case .pause: String(localized: "Pause")
    case .seek: String(localized: "Seek")
    case .sync: String(localized: "Sync")
    case .chapter: String(localized: "Chapter")
    case .timerStarted: String(localized: "Timer Started")
    case .timerCompleted: String(localized: "Timer Completed")
    case .timerExtended: String(localized: "Timer Extended")
    }
  }

  var color: Color {
    switch self {
    case .play: .green
    case .pause: .orange
    case .seek: .blue
    case .sync: .purple
    case .chapter: .brown
    case .timerStarted: .indigo
    case .timerCompleted: .red
    case .timerExtended: .teal
    }
  }
}

#Preview {
  List {
    PlaybackHistoryRow(model: .init(actionType: .play, position: 10000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .pause, position: 20000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .seek, position: 30000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .sync, position: 40000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .chapter, position: 50000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .timerStarted, position: 60000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .timerCompleted, position: 70000, timestamp: Date()))
    PlaybackHistoryRow(model: .init(actionType: .timerExtended, position: 75000, timestamp: Date()))
  }
}
